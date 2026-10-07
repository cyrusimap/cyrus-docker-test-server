#!/usr/bin/perl

# The annotation_callout daemon: on every append, set the message's preview
# annotation (jmap_preview_annot) as Fastmail's annotator does, so JMAP and
# IMAP PREVIEW return real previews.  Run by Cyrus master (cyrus.conf
# DAEMON), in the foreground, as the cyrus user.

package TestServer::Annotator;

use v5.36;

use base qw(Cyrus::Annotator::Daemon);

use Encode qw(encode_utf8);
use Getopt::Long;
use POSIX ();

use lib '/srv/testserver/lib';
use TestServer::Preview qw(preview_for_message);

use constant PREVIEW_ANNOT => '/vendor/messagingengine.com/preview';

sub annotate_message ($self, $message) {
  my $preview = eval { preview_for_message($message) };
  if (!defined $preview) {
    warn "annotator: no preview for $message->{filename}: $@";
    $preview = '';
  }

  $message->set_shared_annotation(PREVIEW_ANNOT, encode_utf8($preview));

  return 0;
}

# Net::Server leaves SIGQUIT blocked if it starts that way, and Cyrus master
# may use it to stop us.
POSIX::sigprocmask(POSIX::SIG_UNBLOCK(), POSIX::SigSet->new(POSIX::SIGQUIT()));

my $socket  = '/var/run/cyrus/annotator.sock';
my $pidfile = '/var/run/cyrus/annotator.pid';
GetOptions(
  'socket=s'  => \$socket,
  'pidfile=s' => \$pidfile,
) or die "usage: $0 [--socket PATH] [--pidfile PATH]\n";
@ARGV = ();   # Net::Server reads @ARGV too

# A socket left by a previous run would stop us binding.
unlink $socket;

TestServer::Annotator->run(
  port       => "$socket|unix",
  pid_file   => $pidfile,
  background => 0,   # master expects its DAEMONs in the foreground
  user       => 'cyrus',
  group      => 'mail',
);
