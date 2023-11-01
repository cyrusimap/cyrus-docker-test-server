#!/usr/bin/perl -w

use File::Slurp;

my $src = shift;
my $dst = shift;

my $data = read_file($src);

$data =~ s[{([^}]+)}][$ENV{$1}//'']egs;

open FH, ">$dst";
print FH $data;
close FH;
chmod 0755, $dst;
