#!/usr/bin/env perl

use 5.014;
use strict;
use warnings;
use File::Basename;
use autodie qw(open);
use Getopt::Long;

my $fasta;
my $fastq;
my $outfile;
my $help;

GetOptions(
	   'fa|fasta=s'   => \$fasta,
	   'fq|fastq=s'   => \$fastq,
	   'o|outfile=s'  => \$outfile,
	   'h|help'       => \$help,
	   );

usage() and exit(0) if $help;

if (!$fasta || !$fastq || !$outfile) {
    say "\nERROR: No input was given.";
    usage();
    exit(1);
}

unless (-e $fasta && -e $fastq) {
    say "\nERROR: One or more input files not found.";
    usage();
    exit(1);
}

my $fqct = 0;
my ($fa_idx, $fact) = make_fasta_index($fasta);
my $fq = get_fh($fastq);
open my $out, '>', $outfile;

my ($name, $comm, $seq, $qual);
my @aux = undef;
while (($name, $comm, $seq, $qual) = readfq(\*$fq, \@aux)) {
    if (exists $fa_idx->{$name}) {
	$fqct++;
	my $seq_match;
	#($seq_match = $seq) =~ /($fa_idx->{$name})/;
	($seq_match = $fa_idx->{$name}) =~ /($seq)/;
	my $seqlen = length($seq_match);
	my $qual_region = substr $qual, 0, $seqlen;
	say $out join "\n", "@".$name, $seq_match, q{+}, $qual_region;
    }
}
close $fq;
close $out;

say STDERR "$$fact sequences from $fasta were indexed.";
say STDERR "$fqct sequences were matched in $fastq and written to $fastq.";

#
# methods
#
sub make_fasta_index {
    my ($fasta) = @_;

    my $fact = 0;
    my $fa = get_fh($fasta);
    my %index;
    my ($name, $comm, $seq, $qual);
    my @aux = undef;
    while (($name, $comm, $seq, $qual) = readfq(\*$fa, \@aux)) {
	$fact++;
	$index{$name} = $seq;
    }
    close $fa;
    return \%index, \$fact;
}

sub get_fh {
    my ($file) = @_;

    my $fh;
    if ($file =~ /\.gz$/) {
        open $fh, '-|', 'zcat', $file or die "\nERROR: Could not open file: $file\n";
    }
    elsif ($file =~ /\.bz2$/) {
        open $fh, '-|', 'bzcat', $file or die "\nERROR: Could not open file: $file\n";
    }
    else {
        open $fh, '<', $file or die "\nERROR: Could not open file: $file\n";
    }

    return $fh;
}

sub readfq {
    my ($fh, $aux) = @_;
    @$aux = [undef, 0] if (!@$aux);
    return if ($aux->[1]);
    if (!defined($aux->[0])) {
        while (<$fh>) {
            chomp;
            if (substr($_, 0, 1) eq '>' || substr($_, 0, 1) eq '@') {
                $aux->[0] = $_;
                last;
            }
        }
        if (!defined($aux->[0])) {
            $aux->[1] = 1;
            return;
        }
    }
    my ($name, $comm);
    defined $_ && do {
        ($name, $comm) = /^.(\S+)(?:\s+)(\S+)/ ? ($1, $2) : 
	                 /^.(\S+)/ ? ($1, '') : ('', '');
    };
    my $seq = '';
    my $c;
    $aux->[0] = undef;
    while (<$fh>) {
        chomp;
        $c = substr($_, 0, 1);
        last if ($c eq '>' || $c eq '@' || $c eq '+');
        $seq .= $_;
    }
    $aux->[0] = $_;
    $aux->[1] = 1 if (!defined($aux->[0]));
    return ($name, $comm, $seq) if ($c ne '+');
    my $qual = '';
    while (<$fh>) {
        chomp;
        $qual .= $_;
        if (length($qual) >= length($seq)) {
            $aux->[0] = undef;
            return ($name, $comm, $seq, $qual);
        }
    }
    $aux->[1] = 1;
    return ($name, $seq);
}

sub usage {
    my $script = basename($0);
  print STDERR <<END
USAGE: $script -fa seqs.fa -fq seqs.fq -o myseqs.fq 

Required:
    -fa|fasta   :    Fasta file of sequences to map IDs and lengths
    -fq|fastq   :    Fastq file to pull reads from
    -o|outfile  :    The file to place the selected reads.

Options:
    -h|help     :    Print usage statement.
    -m|man      :    Print full documentation.
END
}
