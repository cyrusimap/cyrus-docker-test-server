#!/usr/bin/perl -w

use Mail::IMAPTalk;
use Cyrus::SyncProto;
use Cyrus::AccountSync;
use File::Slurp;
use JSON::XS;

my $it = Mail::IMAPTalk->new(
  Server => 'localhost',
  Port => 8143,
  Username => 'admin',
  Password => 'admin',
  AuthzUser => 'admin',
  UseSSL => 0,
  UseBlocking => 1,
  UseCompress => 0,
);
my $sp = Cyrus::SyncProto->new($it);
my $as = Cyrus::AccountSync->new($sp);

my $json = decode_json(read_file("/srv/testserver/examples/empty.json"));

# Discover the other-users namespace prefix (e.g. "Other Users/" with altnamespace)
my $ns = $it->namespace();
my $prefix = $ns->[1][0][0] // 'Other Users/';

for my $userid (map { "user$_" } 1..5) {
  print "making user $userid\n";
  $as->delete_user(username => $userid);
  $as->undump_user(username => $userid, data => $json);
  # sync/undump doesn't set ACLs, so grant the user full rights on all mailboxes
  my $user_mbox = $prefix . $userid;
  my $folders = $it->list($user_mbox, '*') || [];
  for my $mbox ($user_mbox, map { $_->[2] } @$folders) {
    $it->setacl($mbox, $userid, "lrswipkxtecdan");
    $it->setacl($mbox, "admin", "lrswipkxtecdan");
  }
}

$it->logout();
