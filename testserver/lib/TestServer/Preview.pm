package TestServer::Preview;

# Message previews as Fastmail's annotator makes them, so that
# Email/get's "preview" (read from jmap_preview_annot) is what clients see
# against Fastmail.  This is a port of the Fastmail annotator: the body part
# chosen, how it is decoded, and how the text is cleaned and cut.

use v5.36;

use Encode qw(decode);
use Encode::Detect::Detector;
use HTML::Entities qw(decode_entities);
use HTML::Quoted;
use MIME::Base64 qw(decode_base64);
use MIME::QuotedPrint qw(decode_qp);

use Exporter 'import';
our @EXPORT_OK = qw(preview_for_message make_preview clean_body_text decode_body);

# Raw (still transfer-encoded) bytes read from the chosen part.
my $MAX_BODY_CONTENT = 65536;

# The preview for a Cyrus::Annotator::Message, as Perl characters.
sub preview_for_message ($message) {
  my $body = get_body($message) // return '';
  return make_preview($body);
}

# Adapted from Mail::IMAPTalk's find_message: the text/plain and text/html
# parts that make up the message body.
sub find_message ($bodystructure) {
  state %known_text_parts = map { $_ => 1 } qw(plain html text);

  my @part_list = ([ undef, $bodystructure, 0, '', \(my $tmp = '') ]);

  my %msg_components;
  while (my $part = shift @part_list) {
    my ($parent, $bs, $pos, $in_multi_list, $multi_type_ref) = @$part;

    my $inside_alt = $in_multi_list =~ /\balternative\b/ ? 1 : 0;

    my ($mt, $st, $sp) = $bs->@{qw(MIME-Type MIME-Subtype MIME-Subparts)};

    # $dt can be "", which is the default, inline.
    my $dt = $bs->{'Disposition-Type'} // '';
    my $cd = $bs->{'Content-Disposition'} // {};

    if ($mt eq 'text' && ($dt ne 'attachment' && !$cd->{filename} && !$cd->{'filename*'})) {
      if ($known_text_parts{$st}) {
        my $ut = $st eq 'plain' ? 'text' : $st;

        if (!exists $msg_components{$ut}) {
          # An html part in a multipart/mixed is not an alternative
          # representation unless it is the first part.
          unless ($st eq 'html' && $parent
                  && $parent->{'MIME-Subtype'} eq 'mixed' && $pos > 0) {
            $msg_components{$ut} ||= $bs;
          }
        }
        # A tiny or empty part is replaced by a later one with content.
        elsif (($msg_components{$ut}{Size} <= 10 && $bs->{Size} > 10)
            || ($msg_components{$ut}{Lines} < 1 && $bs->{Lines} > 0)) {
          $msg_components{$ut} = $bs;
        }

        next;
      }
    } elsif ($mt eq 'multipart') {
      my $pos = 0;
      my $multi_type_ref = '';
      my $sub_multi_list = join ",", ($in_multi_list or ()), $st;
      my @sub_parts = map { [ $bs, $_, $pos++, $sub_multi_list, \$multi_type_ref ] } @$sp;

      # Look inside signed/alternative/related (and inline) parts first,
      # anything else after the rest of this level.
      if ($st eq 'signed' || $st eq 'alternative' || $st eq 'related' || $dt ne 'attachment') {
        unshift @part_list, @sub_parts;
      } else {
        push @part_list, @sub_parts;
      }
    }
  }

  return \%msg_components;
}

# The body to preview, HTML preferred: { content => characters, type => 'html'|'text' }.
sub get_body ($message) {
  my $parts = find_message($message->bodystructure);

  my ($part, $type) = ($parts->{html}, 'html');
  ($part, $type) = ($parts->{text}, 'text') if !$part && $parts->{text};
  return undef unless $part;

  my $charset = lc($part->{'Content-Type'}{charset} // '');
  my $content = decode_body(read_raw_part($message, $part, $MAX_BODY_CONTENT), $charset);

  return { content => $content, type => $type };
}

# Up to $nbytes of the part, transfer-decoded but still in its charset.
# (Cyrus::Annotator::Message->read_part_content also decodes the charset,
# its own way; the preview needs decode_body's.)
sub read_raw_part ($message, $part, $nbytes) {
  my $fh = $message->fh;
  $nbytes = $part->{Size} if $part->{Size} < $nbytes;
  seek $fh, $part->{Offset}, 0 or die "Cannot seek: $!";
  my $content = '';
  defined read($fh, $content, $nbytes) or die "Cannot read: $!";

  my $cte = lc($part->{'Content-Transfer-Encoding'} // '');
  if ($cte eq 'base64') {
    # Drop anything that isn't base64, and a trailing partial quad.
    $content =~ tr{A-Za-z0-9+/=}{}cd;
    my $extra = length($content) % 4;
    $content = substr($content, 0, -$extra) if $extra;
    $content = decode_base64($content);
  } elsif ($cte eq 'quoted-printable') {
    # Drop a trailing partial escape.
    $content =~ s/=.?$//;
    $content = decode_qp($content);
  }

  return $content;
}

# Octets in $charset to characters, tolerating mislabelled mail: 8-bit
# us-ascii is tried as UTF-8 then windows-1252, and anything else falls back
# to UTF-8 and then detection.  Returns the octets unchanged if nothing fits.
sub decode_body ($body, $charset) {
  $charset = lc($charset || 'us-ascii');

  # Fix up badly formatted iso charsets, and quoted ones.
  $charset =~ s/^(iso)[\-_]?(\d+)[\-_](\d+)[\-_]?\w*/$1-$2-$3/;
  $charset =~ s/^'(.*)'$/$1/;

  if ($charset eq 'utf-8') {
    # Rejoin a UTF-8 sequence split by a line wrap.
    $body =~ s/([\x80-\xff])\r?\n[ \t]{0,10}([\x80-\xbf])/$1$2/g;
  } elsif ($charset eq 'iso-8859-1' || $charset eq 'iso-8859-15') {
    # windows-1252 is a superset with characters in \x80-\x9f.
    $charset = 'windows-1252' if $body =~ /[\x80-\x9f]/;
  }

  # Octets that need decoding: 8-bit, or ESC as used by shift encodings.
  my $to_dec = $body =~ tr/\x1b\x80-\xff/\x1b\x80-\xff/;
  return $body unless $to_dec || $charset eq 'utf-7';

  my @charsets = $charset eq 'us-ascii'
    ? ('utf-8', 'windows-1252')
    : ($charset, ($charset ne 'utf-8' ? 'utf-8' : ()), sub { Encode::Detect::Detector::detect(shift) });

  while (my $cs = shift @charsets) {
    $cs = $cs->($body) || next if ref $cs;

    my $errs = 0;
    my $decoded = eval { decode($cs, $body, sub { $errs++; "" }) } // next;

    # Too many characters that would not decode: try the next one.
    next if $errs > 2 && $to_dec > 2 && $errs / $to_dec > 0.05;

    return $decoded;
  }

  return $body;
}

my $html_test_tags = qr{</?(?:p|div|span|b|i|u|table|tr|td|a|font|img|br)\b[^>]*>}i;

# The body's text as lines, without markup, quoted text, attribution lines
# or leading salutations, each line at most about 140 characters.
sub clean_body_text ($content, $type) {
  # Text that is really HTML.
  if ($type eq 'text' && $content =~ /^\s*</) {
    $type = 'html' if (() = $content =~ /$html_test_tags/g) > 4;
  }

  # Remove quoted sections from HTML.
  if ($type eq 'html') {
    eval {
      my $struct = HTML::Quoted->extract($content);
      @$struct = grep {; ref $_ eq 'HASH' && keys %$_ } @$struct;
      my $new = HTML::Quoted->combine_hunks($struct);
      $content = $new if $new =~ /\S/;
      1;
    } or warn "failed to strip quoted section from preview: $@";
  }

  local $_ = $content;

  if ($type ne 'text') {
    s{<(head|script|style)\b[^>]*>.*?(?:</\1\b[^>]*>|\z)}{}isg;
    s{<!--.*?(?:-->|\z)}{}isg;
    s{</(?:p|div|h\d|td)\b[^>]*>}{\n}isg;
    s{<br\b[^>]*>}{\n}isg;
    s{<[^>]*(?:>|\z)}{}isg;
  }

  my $decode_entities = $type eq 'html' ? 1 : 0;
  if ($type eq 'text' && /&#/) {
    $decode_entities = 1 if (() = /&#(?:\d+|x[0-9a-f]+);/ig) > 4;
  }
  $_ = decode_entities($_) if $decode_entities;

  s/^(?:[ \t]*\r?\n)+//gm;                                  # blank lines
  s/[\x{200b}\x{200c}\x{200d}\x{200e}\x{200f}]+\x{feff}//g; # junk sequences
  s/([ -=_#\x{ad}])\x{34f}/$1/g;
  s/(?:\x{200c}?[ \t\x{a0}\x{ad}]\x{200c}?)+/ /g;           # spaces, nbsp, tabs
  s/^\s+//;
  s/([-=_#])\1{3,}/$1$1$1/g;                                # ---- => ---

  my @lines = split /\r?\n/, $_;

  # Skip quoted lines, attribution lines and salutations at the start.
  my @last;
  while (defined($_ = shift @lines)) {
    s/\A\s+//;
    s/\s+\z//;
    next if /^(?:[\>\|] ?)*\s*$/;
    push(@last, $_) && next if /^(?:[\>\|] ?)+/;
    push(@last, $_) && next
      if /\swrote:$/i || /\ssaid:$/i || /^quoting\s.*:$/i || /^\* .+?\d+\]:$/i;
    push(@last, $_, shift(@lines)) && next
      if @lines && /^On / && $lines[0] =~ /^(?:wrote|said):/;
    push(@last, $_) && next
      if @lines && /^(Dear|Hello|Hi|Hey)( \S+){0,4}[,:!]$/n;
    unshift @lines, $_;
    last;
  }

  # If that was everything, preview it anyway.
  @lines = @last if !@lines;

  # Wrap long lines.
  @lines = map {
    my @r;
    while (length($_) > 140) {
      s/^(.{18,90})( )// || s/^(.{90,120}?)( )// || s/^(.{120})()//;
      push @r, $1;
    }
    (@r, $_);
  } @lines;

  return @lines;
}

# The preview: whole lines, at least 3 of them or 160 characters, on one
# line with whitespace collapsed.
sub make_preview ($body) {
  my @lines;
  eval {
    local $SIG{ALRM} = sub { die "Timeout\n" };
    alarm 10;
    @lines = clean_body_text($body->{content}, $body->{type});
    alarm 0;
    1;
  } or do {
    alarm 0;
    warn "error while generating preview: $@";
  };

  my ($pos, $length) = (0, 0);
  while ($length < 160 && $pos < @lines) {
    $length += length($lines[$pos++]) + 1;
  }
  $pos = 3 if $pos < 3;
  splice(@lines, $pos) if $pos < @lines;

  my $preview = join q{ }, @lines;
  $preview =~ s/\A\s+//;
  $preview =~ s/\s+\z//;
  $preview =~ s/\s+/ /g;

  return $preview;
}

1;
