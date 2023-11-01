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

my $json = decode_json(read_file("/srv/cyrus-docker-test-server.git/examples/empty.json"));

for my $userid (map { "user$_" } 1..5) {
  print "making user $userid\n";
  $as->delete_user(username => $userid);
  $as->undump_user(username => $userid, data => $json);
}

$it->logout();
