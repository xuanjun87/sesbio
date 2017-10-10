#!/usr/bin/env perl

##NB: This takes an annotation file from Transposome and basically
##    generates a summary that is less detailed (for fast inspection)
##    than the summary report generated by Transposome.

use 5.010;
use strict;
use warnings;
use autodie;

my %res;
my $usage = "perl $0 annotations_summary.tsv";
my $file = shift or die $usage;
open my $in, '<', $file;

while (<$in>) {
    chomp;
    next if /^ReadNum/;
    my @f = split;
    push @{$res{$f[1]}}, { $f[2] => $f[4] };
}
close $in;

my %sfamtot;

for my $sfamh (keys %res) {
    for my $sfam (@{$res{$sfamh}}) {
	my $sfam_tot = 0;
	for my $fam (keys %$sfam) {
	   $sfamtot{$fam} += $sfam->{$fam};
	}
    }
    for my $sfamname (reverse sort { $sfamtot{$a} <=> $sfamtot{$b} } keys %sfamtot) {
	say join "\t", $sfamh, $sfamname, $sfamtot{$sfamname};
    }
    %sfamtot = ();
}
	
