#!/usr/bin/perl

use Mojolicious::Lite;
use Mail::IMAPTalk;
use Cyrus::SyncProto;
use Cyrus::AccountSync;
use JSON::XS;
use File::Slurp;
use Template;
use IO::Compress::Zip     qw($ZipError);
use IO::Uncompress::Unzip qw($UnzipError);
use Mail::JMAPTalk;
use Data::UUID;
use POSIX qw(strftime);

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
    my $ns = $imap->namespace();
    my $prefix = $ns->[1][0][0] // 'Other Users/';
    my $folders = $imap->list($prefix, '%') || [];
    for my $entry (@$folders) {
      my $name = $entry->[2];
      (my $user = $name) =~ s/^\Q$prefix\E//;
      push @users, $user if $user;
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
  _set_user_quota($userid, $json->{quota_kb}) if defined $json->{quota_kb};
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

# --- PDPA (Personal Data Portability Archive) ---

# Export: GET /api/:userid/pdpa  → application/zip
get '/api/:userid/pdpa' => sub {
  my $c      = shift;
  my $userid = $c->param('userid');
  my %files;

  $files{'archive.json'} = encode_json({
    archive => {
      id        => lc(Data::UUID->new->create_str()),
      name      => "Export for $userid",
      timestamp => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime()),
      version   => '1',
      generator => 'cyrus-docker-test-server',
    },
    dataset => {
      extent      => 'full',
      timezone    => 'UTC',
      languagetag => 'en',
    },
  });

  _connect();
  eval { _pdpa_export_mail($userid, \%files) };
  warn "PDPA mail export error: $@" if $@;
  eval { _pdpa_export_contacts($userid, \%files) };
  warn "PDPA contacts export error: $@" if $@;
  eval { _pdpa_export_calendars($userid, \%files) };
  warn "PDPA calendars export error: $@" if $@;
  eval { $it->logout() };

  my $zip = _files_to_zip(%files);
  $c->res->headers->content_type('application/zip');
  $c->res->headers->header('Content-Disposition',
    qq{attachment; filename="${userid}-pdpa.zip"});
  $c->render(data => $zip);
};

# Import: POST /api/:userid/pdpa  ← application/zip body
post '/api/:userid/pdpa' => sub {
  my $c      = shift;
  my $userid = $c->param('userid');
  my $body   = $c->req->body;

  unless (length($body // '')) {
    return $c->render(json => { error => 'empty body' }, status => 400);
  }

  my %files = _unzip($body);

  _connect();
  my @errors;
  eval { _pdpa_import_mail($userid, \%files) };
  push @errors, "mail: $@" if $@;
  eval { _pdpa_import_contacts($userid, \%files) };
  push @errors, "contacts: $@" if $@;
  eval { _pdpa_import_calendars($userid, \%files) };
  push @errors, "calendars: $@" if $@;
  eval { $it->logout() };

  if (@errors) {
    $c->render(json => { errors => \@errors }, status => 207);
  } else {
    $c->render(json => { ok => \1 }, status => 200);
  }
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
  _set_user_quota($userid, $json->{quota_kb}) if defined $json->{quota_kb};
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

# --- Helpers ---

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
  my $ns = $it->namespace();
  my $prefix = $ns->[1][0][0] // 'Other Users/';
  my $user_mbox = $prefix . $userid;
  my $folders = $it->list($user_mbox, '*') || [];
  for my $mbox ($user_mbox, map { $_->[2] } @$folders) {
    $it->setacl($mbox, $userid, "lrswipkxtecdan");
    $it->setacl($mbox, "admin", "lrswipkxtecdan");
  }
}

sub _set_user_quota {
  my ($userid, $quota_kb) = @_;
  $it->_imap_cmd("SETQUOTA", 0, "", "user/$userid", ["STORAGE", $quota_kb + 0]);
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

# --- PDPA helpers ---

sub _jmap_call {
  my ($userid, $using, $calls) = @_;
  my $jmap = Mail::JMAPTalk->new(
    scheme   => 'http',
    host     => 'localhost',
    port     => $HTTP_PORT,
    url      => '/jmap/',
    user     => $userid,
    password => 'password',
    using    => $using,
  );
  return $jmap->CallMethods($calls);
}

# admin-namespace mailbox name → PDPA folder path (e.g. "Other Users/u/Sent" → "Sent")
sub _mbox_to_pdpa_path {
  my ($mbox, $prefix) = @_;
  return 'INBOX' if $mbox eq $prefix;
  my $rel = substr($mbox, length($prefix) + 1);  # strip "Other Users/userid/"
  return $rel;  # separator is already "/" in admin namespace
}

# PDPA folder path → admin-namespace mailbox name
sub _pdpa_path_to_mbox {
  my ($path, $prefix) = @_;
  return $prefix if $path eq 'INBOX';
  return "$prefix/$path";
}

sub _files_to_zip {
  my (%files) = @_;
  my @paths = sort keys %files;
  return '' unless @paths;

  my $first = shift @paths;
  my $zip_data = '';
  my $zip = IO::Compress::Zip->new(\$zip_data, Name => $first)
    or die "Zip error: $ZipError\n";
  $zip->print($files{$first});

  for my $path (@paths) {
    $zip->newStream(Name => $path)
      or die "Zip stream error: $ZipError\n";
    $zip->print($files{$path});
  }
  $zip->close();
  return $zip_data;
}

sub _unzip {
  my ($zip_content) = @_;
  my %files;
  my $u = IO::Uncompress::Unzip->new(\$zip_content)
    or die "Cannot read zip: $UnzipError\n";
  do {
    my $hdr  = $u->getHeaderInfo;
    my $name = $hdr->{Name} // '';
    next if $name =~ m{/$};  # skip directory entries
    local $/;
    $files{$name} = <$u> // '';
  } while $u->nextStream() > 0;
  return %files;
}

sub _pdpa_export_mail {
  my ($userid, $files) = @_;

  my $ns     = $it->namespace();
  my $prefix = ($ns->[1][0][0] // 'user/') . $userid;

  # List all mailboxes (recursive) plus the inbox itself
  my $listed  = $it->list($prefix, '*') || [];
  my @mboxes  = ($prefix, map { $_->[2] } @$listed);

  for my $mbox (sort @mboxes) {
    my $path = _mbox_to_pdpa_path($mbox, $prefix);

    $it->select($mbox) or next;
    my $uidvalidity = $it->get_response_code('uidvalidity') // 1;

    my $msgs = $it->fetch('1:*', '(UID FLAGS BODY.PEEK[])') // {};
    my @items;
    for my $seq (sort { $a <=> $b } keys %$msgs) {
      my $m    = $msgs->{$seq};
      my $uid  = $m->{uid}   or next;
      my $body = $m->{body}  // next;
      my @flags    = grep { /^\\/ } @{ $m->{flags} // [] };

      my $filename = "$uid.eml";
      $files->{"mail/$path/$filename"} = $body;
      push @items, { uid => "${uidvalidity}.${uid}", filename => $filename,
                     (@flags ? (flags => \@flags) : ()) };
    }

    $files->{"mail/$path/folder.json"} = encode_json({
      name        => $path,
      uid         => "$uidvalidity",
      uidvalidity => $uidvalidity + 0,
      items       => \@items,
    });
  }
}

sub _pdpa_export_contacts {
  my ($userid, $files) = @_;
  my $using = ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:contacts'];

  my $ab_res = _jmap_call($userid, $using, [['AddressBook/get', {}, 'a']]);
  for my $ab (@{ $ab_res->[0][1]{list} // [] }) {
    my $name = $ab->{name} // $ab->{id};
    my $dir  = "contacts/$name";

    my $q_res  = _jmap_call($userid, $using,
      [['ContactCard/query', { filter => { inAddressBook => $ab->{id} } }, 'q']]);
    my $ids    = $q_res->[0][1]{ids} // [];

    my @items;
    if (@$ids) {
      my $g_res = _jmap_call($userid, $using, [['ContactCard/get', { ids => $ids }, 'g']]);
      for my $card (@{ $g_res->[0][1]{list} // [] }) {
        my $uid      = $card->{uid} // $card->{id};
        my $filename = "$uid.json";
        $files->{"$dir/$filename"} = encode_json($card);
        push @items, { uid => $uid, filename => $filename };
      }
    }

    $files->{"$dir/folder.json"} = encode_json({
      name  => $name,
      uid   => $ab->{id},
      items => \@items,
    });
  }
}

sub _pdpa_export_calendars {
  my ($userid, $files) = @_;
  my $using = ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:calendars'];

  my $cal_res = _jmap_call($userid, $using, [['Calendar/get', {}, 'c']]);
  for my $cal (@{ $cal_res->{methodResponses}[0][1]{list} // [] }) {
    my $name = $cal->{name} // $cal->{id};
    my $dir  = "calendars/$name";

    my $q_res  = _jmap_call($userid, $using,
      [['CalendarEvent/query', { filter => { inCalendar => $cal->{id} } }, 'q']]);
    my $ids    = $q_res->[0][1]{ids} // [];

    my @items;
    if (@$ids) {
      my $g_res = _jmap_call($userid, $using, [['CalendarEvent/get', { ids => $ids }, 'g']]);
      for my $event (@{ $g_res->[0][1]{list} // [] }) {
        my $uid      = $event->{uid} // $event->{id};
        my $filename = "$uid.json";
        $files->{"$dir/$filename"} = encode_json($event);
        push @items, { uid => $uid, filename => $filename };
      }
    }

    $files->{"$dir/folder.json"} = encode_json({
      name  => $name,
      uid   => $cal->{id},
      items => \@items,
    });
  }
}

sub _pdpa_import_mail {
  my ($userid, $files) = @_;

  my $ns     = $it->namespace();
  my $prefix = ($ns->[1][0][0] // 'user/') . $userid;

  # Find all mail folder.json files
  my %folders;
  for my $path (keys %$files) {
    next unless $path =~ m{^mail/(.+)/folder\.json$};
    $folders{$1} = eval { decode_json($files->{$path}) } // {};
  }

  for my $folder_path (sort keys %folders) {
    my $meta  = $folders{$folder_path};
    my $mbox  = _pdpa_path_to_mbox($folder_path, $prefix);

    eval { $it->create($mbox) };  # ignore error if already exists

    for my $item (@{ $meta->{items} // [] }) {
      my $filename = $item->{filename} or next;
      my $body     = $files->{"mail/$folder_path/$filename"} or next;
      my @flags = grep { !/^\\Recent$/i } @{ $item->{flags} // [] };
      $it->append($mbox, (@flags ? (\@flags) : ()), $body)
        or warn "APPEND to $mbox failed: " . ($it->get_last_error() // '?');
    }
  }
}

sub _pdpa_import_contacts {
  my ($userid, $files) = @_;
  my $using = ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:contacts'];

  my %ab_dirs;
  for my $path (keys %$files) {
    next unless $path =~ m{^contacts/(.+)/folder\.json$};
    $ab_dirs{$1} = eval { decode_json($files->{$path}) } // {};
  }

  for my $dir (sort keys %ab_dirs) {
    my $meta = $ab_dirs{$dir};

    my $cr = _jmap_call($userid, $using, [
      ['AddressBook/set', { create => { ab => { name => $meta->{name} // $dir } } }, 's'],
    ]);
    my $ab_id = $cr->[0][1]{created}{ab}{id} or next;

    my %cards;
    for my $item (@{ $meta->{items} // [] }) {
      my $filename = $item->{filename} or next;
      my $card = eval { decode_json($files->{"contacts/$dir/$filename"}) } or next;
      delete $card->{id};
      $card->{addressBookIds} = { $ab_id => \1 };
      $cards{ $item->{uid} } = $card;
    }

    _jmap_call($userid, $using, [['ContactCard/set', { create => \%cards }, 's']])
      if %cards;
  }
}

sub _pdpa_import_calendars {
  my ($userid, $files) = @_;
  my $using = ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:calendars'];

  my %cal_dirs;
  for my $path (keys %$files) {
    next unless $path =~ m{^calendars/(.+)/folder\.json$};
    $cal_dirs{$1} = eval { decode_json($files->{$path}) } // {};
  }

  for my $dir (sort keys %cal_dirs) {
    my $meta = $cal_dirs{$dir};

    my $cr = _jmap_call($userid, $using, [
      ['Calendar/set', { create => { cal => { name => $meta->{name} // $dir } } }, 's'],
    ]);
    my $cal_id = $cr->[0][1]{created}{cal}{id} or next;

    my %events;
    for my $item (@{ $meta->{items} // [] }) {
      my $filename = $item->{filename} or next;
      my $event = eval { decode_json($files->{"calendars/$dir/$filename"}) } or next;
      delete $event->{id};
      $event->{calendarIds} = { $cal_id => \1 };
      $events{ $item->{uid} } = $event;
    }

    _jmap_call($userid, $using, [['CalendarEvent/set', { create => \%events }, 's']])
      if %events;
  }
}

app->start;
