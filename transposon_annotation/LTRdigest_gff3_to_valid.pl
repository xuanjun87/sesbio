#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use autodie qw(open);
use Getopt::Long;

my $infile;
my $outfile;
my $usage = "USAGE: $0 -i in.gff3 -o out.gff3\n";

GetOptions(
           'i|infile=s'           => \$infile,
           'o|outfile=s'          => \$outfile,
	  );

if (!$infile || !$outfile) {
    print $usage and exit(1);
}

open my $in, '<', $infile;
open my $seq, '<', $infile;
open my $out, '>', $outfile;

my @contig = grep {/# (\w)/} <$seq>;
close $seq;
my $contigID = get_contig(@contig); #TODO: this is silly, use map/split block

my @gff = <$in>;
for my $line (@gff) {
    chomp $line;
    if ($line =~ m/^##gff-version /) {
	say $out $line;
    }
    if ($line =~ m/^##sequence-region /) {
	my @seq_region = split /\s+/, $line;
	say $out join q{ }, $seq_region[0], $contigID, $seq_region[2], $seq_region[3];
    }
    if ($line =~ m/^seq/) {
	my @gff_fields = split /\s+/, $line;
	my $correctID = $gff_fields[0];
	$correctID =~ s/(\w*)/$contigID/;

	#my @corrected_fields = $correctID."\t".        # Column 1: "seqid"
        #                       $gff_fields[1]."\t".    # Column 2: "source"
	#			$gff_fields[2]."\t".    # Column 3: "type"        ==> repeat_region is not a correct SO term.
	#			$gff_fields[3]."\t".    # Column 4: "start" 
	#			$gff_fields[4]."\t".    # Column 5: "end"
	#			$gff_fields[5]."\t".    # Column 6: "score"
	#			$gff_fields[6]."\t".    # Column 7: "strand"
	#			$gff_fields[7]."\t".    # Column 8: "phase"
	#			$gff_fields[8]."\n";    # Column 9: "attributes"  ==> Need to fix here too. (Parent=repeat_region2)
	
	say $out join "\t", $correctID, @gff_fields[1..8];
    }
}
close $in;
close $out;

sub get_contig {
    my @name = @_;
    for (@name) {
	my ($comm, $contig) = split /\s+/, $_;
	return $contig;
    }
}

