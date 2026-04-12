#!/usr/bin/perl

use Mojolicious::Lite;
use Mail::IMAPTalk;
use Cyrus::SyncProto;
use Cyrus::AccountSync;
use JSON::XS;
use File::Slurp;
use Template;

$| = 1;

my $it;

my $TEMPLATE_DIR = app->home->child('templates')->to_string;
my $tt = Template->new(
  INCLUDE_PATH => $TEMPLATE_DIR,
  ENCODING     => 'utf8',
  WRAPPER      => 'layout.html.tt',
);

# Port config from environment
my $WEB_PORT   = $ENV{WEBPORT}   // 8001;
my $IMAP_PORT  = $ENV{IMAPPORT}  // 8143;
my $POP3_PORT  = $ENV{POP3PORT}  // 8110;
my $HTTP_PORT  = $ENV{HTTPPORT}  // 8080;
my $LMTP_PORT  = $ENV{LMTPPORT}  // 8024;
my $SIEVE_PORT = $ENV{SIEVEPORT} // 4190;

sub _common_vars {
  return (
    web_port   => $WEB_PORT,
    imap_port  => $IMAP_PORT,
    pop3_port  => $POP3_PORT,
    http_port  => $HTTP_PORT,
    lmtp_port  => $LMTP_PORT,
    sieve_port => $SIEVE_PORT,
  );
}

sub render_tt {
  my ($c, $template, %vars) = @_;
  $vars{title} //= 'Cyrus Test Server';
  my $output = '';
  if ($tt->process($template, { _common_vars(), %vars }, \$output)) {
    $c->render(data => $output, format => 'html');
  } else {
    $c->render(text => 'Template error: ' . $tt->error(), status => 500);
  }
}

# --- HTML Web Interface ---

get '/' => sub {
  my $c = shift;
  render_tt($c, 'index.html.tt', title => 'Home');
};

get '/ui/users' => sub {
  my $c = shift;
  my @users;
  my $err;
  eval {
    my $imap = Mail::IMAPTalk->new(
      Server => 'localhost',
      Port => $IMAP_PORT,
      Username => 'admin',
      Password => 'admin',
      AuthzUser => 'admin',
      UseSSL => 0,
      UseBlocking => 1,
      UseCompress => 0,
    );
    my $folders = $imap->list('user.', '%') || [];
    for my $entry (@$folders) {
      my $name = $entry->[2];
      if ($name =~ m{^user[./](.+)$}) {
        push @users, $1;
      }
    }
    $imap->logout();
  };
  $err = $@ if $@;
  render_tt($c, 'users.html.tt',
    title         => 'Users',
    users         => [ sort @users ],
    error         => $err,
    flash_success => $c->flash('success'),
    flash_error   => $c->flash('error'),
  );
};

get '/ui/users/:userid' => sub {
  my $c = shift;
  my $userid = $c->param('userid');
  my $as = _connect();
  my $data = $as->dump_user(username => $userid);
  eval { $it->logout() };
  if ($data) {
    my $json = JSON::XS->new->pretty->canonical->encode($data);
    render_tt($c, 'user_detail.html.tt',
      title  => $userid,
      userid => $userid,
      json   => $json,
    );
  }
  else {
    render_tt($c, 'error.html.tt',
      title   => 'Error',
      message => "User '$userid' not found",
    );
  }
};

post '/ui/users' => sub {
  my $c = shift;
  my $userid = $c->param('userid');
  unless ($userid && $userid =~ /^[a-zA-Z0-9._-]+$/) {
    $c->flash(error => "Invalid username. Use only letters, numbers, dots, hyphens, underscores.");
    return $c->redirect_to('/ui/users');
  }
  eval {
    my $json = decode_json(read_file("/srv/testserver/examples/empty.json"));
    my $as = _connect();
    _delete_user_completely($as, $userid);
    $as->undump_user(username => $userid, data => $json);
    _set_user_acls($userid);
    eval { $it->logout() };
  };
  if ($@) {
    $c->flash(error => "Failed to create user: $@");
  } else {
    $c->flash(success => "User '$userid' created successfully.");
  }
  $c->redirect_to('/ui/users');
};

post '/ui/users/:userid/delete' => sub {
  my $c = shift;
  my $userid = $c->param('userid');
  eval {
    my $as = _connect();
    _delete_user_completely($as, $userid);
    eval { $it->logout() };
  };
  if ($@) {
    $c->flash(error => "Failed to delete user: $@");
  } else {
    $c->flash(success => "User '$userid' deleted.");
  }
  $c->redirect_to('/ui/users');
};

# --- JSON API ---

get '/api/:userid' => sub {
  my $c   = shift;
  my $userid = $c->param('userid');
  my $as = _connect();
  my $data = $as->dump_user(username => $userid);
  eval { $it->logout() };
  if ($data) {
    $c->render(json => $data);
  }
  else {
    $c->render(text => 'Not found.', status => 404);
  }
};

put '/api/:userid' => sub {
  my $c   = shift;
  my $userid = $c->param('userid');
  my $json = $c->req->json;
  my $as = _connect();
  _delete_user_completely($as, $userid);
  $as->undump_user(username => $userid, data => $json);
  _set_user_acls($userid);
  $c->render(text => '', status => 204);
  eval { $it->logout() };
};

del '/api/:userid' => sub {
  my $c   = shift;
  my $userid = $c->param('userid');
  my $as = _connect();
  _delete_user_completely($as, $userid);
  $c->render(text => '', status => 204);
  eval { $it->logout() };
};

# Legacy routes (backwards compatibility with existing curl commands)
get '/:userid' => [userid => qr/[^\/]+/] => sub {
  my $c   = shift;
  my $userid = $c->param('userid');
  return $c->reply->not_found if $userid =~ /^(ui|api)$/;
  my $as = _connect();
  my $data = $as->dump_user(username => $userid);
  eval { $it->logout() };
  if ($data) {
    $c->render(json => $data);
  }
  else {
    $c->render(text => 'Not found.', status => 404);
  }
};

put '/:userid' => [userid => qr/[^\/]+/] => sub {
  my $c   = shift;
  my $userid = $c->param('userid');
  return $c->reply->not_found if $userid =~ /^(ui|api)$/;
  my $json = $c->req->json;
  my $as = _connect();
  _delete_user_completely($as, $userid);
  $as->undump_user(username => $userid, data => $json);
  _set_user_acls($userid);
  $c->render(text => '', status => 204);
  eval { $it->logout() };
};

del '/:userid' => [userid => qr/[^\/]+/] => sub {
  my $c   = shift;
  my $userid = $c->param('userid');
  return $c->reply->not_found if $userid =~ /^(ui|api)$/;
  my $as = _connect();
  _delete_user_completely($as, $userid);
  $c->render(text => '', status => 204);
  eval { $it->logout() };
};

# Delete a user and all their tombstone records so the username can be reused.
# AccountSync::delete_user (APPLY UNUSER) removes active mailboxes but leaves
# DELETED.* tombstones (for calendars, addressbooks, and previously deleted
# mailboxes). AccountSync::undump_user refuses to recreate if any records
# remain, so we must UNMAILBOX every tombstone after UNUSER.
sub _delete_user_completely {
  my ($as, $userid) = @_;
  $as->delete_user(username => $userid);
  my $sp = $as->{sync};
  my $info = $sp->dlwrite("GET", "USER", $userid);
  for my $mbox (@{$info->{MAILBOX} // []}) {
    $sp->dlwrite("APPLY", "UNMAILBOX", $mbox->{MBOXNAME});
  }
}

sub _set_user_acls {
  my ($userid) = @_;
  my $folders = $it->list("user.$userid", '*') || [];
  for my $mbox ("user.$userid", map { $_->[2] } @$folders) {
    $it->setacl($mbox, $userid, "lrswipkxtecdan");
    $it->setacl($mbox, "admin", "lrswipkxtecdan");
  }
}

sub _connect {
  $it = Mail::IMAPTalk->new(
    Server => 'localhost',
    Port => $IMAP_PORT,
    Username => 'admin',
    Password => 'admin',
    AuthzUser => 'admin',
    UseSSL => 0,
    UseBlocking => 1,
    UseCompress => 0,
  );
  my $sp = Cyrus::SyncProto->new($it);
  return Cyrus::AccountSync->new($sp);
}

app->start;
