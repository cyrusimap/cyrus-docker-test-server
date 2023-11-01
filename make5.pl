#!/usr/bin/perl -w

use Mail::IMAPTalk;
use Cyrus::SyncProto;
use Cyrus::AccountSync;
use File::Slurp;

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

my $json = read_file("/srv/cyrus-docker-test-server.git/examples/empty.json");

for my $user (map { "user$_" } 1..5) {
  $as->undump_user(username => $userid, data => $json);
}
