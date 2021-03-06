#!/usr/bin/env perl

##Description: Add pair information back to an interleaved file
##             of paired-end reads. Usually this is necessary
##             with Illumina 1.8+ where the pair information is in the comment.
## Alternatively, just use 'pairfq addinfo'

use 5.010;
use strict;
use warnings;
use autodie qw(open);
use Getopt::Long;

my $usage = "\n$0 -i in_fas -o outfile\n\n";
my $infile;
my $outfile;

GetOptions(
	   'i|infile=s'  => \$infile,
	   'o|outfile=s' => \$outfile,
	   );

die $usage if !$infile or !$outfile;

open my $in, '<', $infile;
open my $out, '>', $outfile;

my %seqhash;
my $totalct = 0;
my $dupct   = 0;

{
    local $/ = '>';

    while (my $line = <$in>) {
	chomp $line;
	my ($seqid, @seqparts) = split /\n/, $line;
	my $seq = join '', @seqparts;
	next unless defined $seqid && defined $seq;
	$totalct++;
	if (exists $seqhash{$seqid}) {
	    say $out join "\n", ">".$seqid."/1", $seq;
	    say $out join "\n", ">".$seqid."/2", $seqhash{$seqid};
	    $dupct++;
	}
	$seqhash{$seqid} = $seq;
    }
}
close $in;
close $out;

say "\n=====> $dupct pairs found in $totalct total reads.\n";

