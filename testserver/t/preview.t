use v5.36;
use utf8;

# The preview port must match Fastmail's annotator: these are its cases.

use Test::More;
use Unicode::Normalize qw(NFC NFD);

use FindBin;
use lib "$FindBin::Bin/../lib";
use TestServer::Preview qw(make_preview decode_body);

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw(output failure_output todo_output);

sub preview_ok ($type, $content, $want, $desc) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my $got = make_preview({ content => $content, type => $type });
  ref $want ? like($got, $want, $desc) : is($got, $want, $desc);
}

preview_ok(html => <<~'END', 'This is amazing! You will subscribe or die.', 'simple html');
  <body>
    <h1>This is amazing!</h1>
    <p>You will subscribe or die.</p>
  </body>
  END

preview_ok(html => <<~'END', q{Don't bother.}, 'html with a quoted section');
  <body>
    <p>On December 24, 2020, you wrote:</p>
    <blockquote>
      I am going to find you and give you five dollars.
      <div>This I swear!</div>
    </blockquote>
    <p>Dear Sir,</p>
    <p>Don't bother.</p>
  </body>
  END

preview_ok(text => <<~'END',
  Dear Lucy,

  Your services will no longer be needed.  Please turn in your flaming sword.


  Your friend,
  Y.
  END
  'Your services will no longer be needed. Please turn in your flaming sword. Your friend, Y.',
  'text: salutation dropped, signature kept');

preview_ok(text => <<~"END", qr/^Junk sequences\s*$/, q{junk sequences stripped});
Junk sequences
\x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c} \x{34f} \x{34f} \x{200c}
\x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c} \x{ad}\x{34f} \x{200c}
\x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c} \x{200c}
\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad} \x{34f}\x{ad}
\x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f} \x{ad}\x{34f}
\x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff} \x{200c}\x{200b}\x{200d}\x{200e}\x{200f}\x{feff}
\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}\x{200c}\x{feff}
 \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{34f} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad} \x{ad}
END

preview_ok(text => <<~'END',
  Buffalo Bill ’s
  defunct
           who used to
           ride a watersmooth-silver
                                           stallion
  and break onetwothreefourfive pigeonsjustlikethat
                                                                Jesus

  he was a handsome man
                                  and what i want to know is
  how do you like your blue-eyed boy
  Mister Death
  END
  join(q{ },
    'Buffalo Bill ’s defunct who used to ride a watersmooth-silver',
    'stallion and break onetwothreefourfive pigeonsjustlikethat',
    'Jesus he was a handsome man and what i want to know is'),
  'whole lines up to 160 characters');

preview_ok(html => substr(
    "<html><body><h1>This is fine but...</h1><p>What happens when<i> "
  . "somehow you <b>find yourself <u>stuck inside the <strong>worst <"
  . "/strong></u></b></i> case of nested nonsense you can imagine?!?!"
  . "</body></html>", 0, 128),
  'This is fine but... What happens when somehow you find yourself stuck inside the worst',
  'html truncated mid-tag');

my $q = "There is no greater band than Queensrÿche.";
preview_ok(text => substr(NFC($q), 0, 38), 'There is no greater band than Queensrÿ', 'NFC cut');
preview_ok(text => substr(NFD($q), 0, 38), 'There is no greater band than Queensry', 'NFD cut');

{
  my $html = <<~'END';
    <blockquote>
      something something
      <blockquote>
      All work and no play makes Jack a dull boy.
      </blockquote>
      other thing
      </blockquote>
    <div>sounds good!</div>
    END
  preview_ok(html => substr($html, 0, index($html, 'play')),
    'something something All work and no', 'only quoted content: preview it anyway');
}

{
  my $html = "<blockquote>\n  something something\n</blockquote>\nAll work and no play makes Jack a dull boy.\n";
  preview_ok(html => $html, 'All work and no play makes Jack a dull boy.', 'quote stripped');

  no warnings qw(redefine once);
  local *HTML::Quoted::extract = sub { die "Oh no!\n" };
  local $SIG{__WARN__} = sub {};
  preview_ok(html => $html, 'something something All work and no play makes Jack a dull boy.',
    'quote stripper dies: preview everything');
}

# Charset decoding, as the annotator proxy does it.
is(decode_body("caf\xc3\xa9", 'us-ascii'), "café", '8-bit us-ascii tried as UTF-8');
is(decode_body("\x93a\x94 \x93b\x94 \x93c\x94", q{us-ascii}), "\x{201c}a\x{201d} \x{201c}b\x{201d} \x{201c}c\x{201d}", q{... then windows-1252, when UTF-8 fails on more than 2 and 5%});
is(decode_body("\x93hi\x94", 'iso-8859-1'), "\x{201c}hi\x{201d}", 'iso-8859-1 with C1 bytes is windows-1252');
is(decode_body("caf\xc3\n \xa9", 'utf-8'), "café", 'UTF-8 split by a line wrap rejoined');
is(decode_body("plain", ''), "plain", 'ASCII untouched');

done_testing;
