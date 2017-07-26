#!/usr/bin/env perl

=head1 NAME 
                                                                       
tallymersearch2gff.pl - Compute k-mer frequencies in a genome

=head1 SYNOPSIS    
 
 perl tallymersearch2gff.pl -i contig.fas -t target.fas -k 20 -o contig_target.gff 

=head1 DESCRIPTION

This script will generate a GFF3 file for a query sequence (typically a contig or chromosome)
that can be used with GBrowse or other genome browsers (it's also possible to generate quick
plots with the results with, e.g. R).

=head1 DEPENDENCIES

Non-core Perl modules used are IPC::System::Simple and Try::Tiny.

Tested with:

=over 2

=item *

Perl 5.16.0 (on Mac OS X 10.6.8 (Snow Leopard))

=item *

Perl 5.18.0 (on Red Hat Enterprise Linux Server release 5.9 (Tikanga)) 

=back

=head1 LICENSE

Copyright (C) 2013-2017 S. Evan Staton

This program is distributed under the MIT (X11) License: http://www.opensource.org/licenses/mit-license.php

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and 
associated documentation files (the "Software"), to deal in the Software without restriction, 
including without limitation the rights to use, copy, modify, merge, publish, distribute, 
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software 
is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies 
or substantial portions of the Software.

=head1 AUTHOR 

S. Evan Staton                                                

=head1 CONTACT
 
statonse at gmail dot com

=head1 REQUIRED ARGUMENTS

=over 2

=item -i, --infile

A Fasta file (contig or chromosome) to search.

=item -o, --outfile

The name a GFF3 file that will be created with the search results.

=back

=head1 OPTIONS

=over 2

=item -t, --target

A file of WGS reads to index and search against the input Fasta.

=item -k, --kmerlen

The k-mer length to use for building the index. Integer (Default: 20).

=item --log

Report the log number of counts instead of raw counts. This is often a good option with WGS
data because many regions have very, very high coverage.

=item --quiet

Do not print progress of the program to the screen.

=item --clean

Remove all the files generated by this script. This does not currently touch any of
the Tallymer suffix or index files.

=item -h, --help

Print a usage statement. 

=item -m, --man

Print the full documentation.

=cut

use 5.010;
use strict;
use warnings;
use File::Basename;
use File::Temp;
use File::Find;
use Cwd;
use Sort::Naturally;
use IPC::System::Simple qw(capture system);
use Try::Tiny;
use Bio::DB::HTS::Kseq;
use Getopt::Long;

my ($infile, $outfile, $k, $db, $help, $man, $clean, $debug);
my ($log, $quiet, $filter, $matches, $ratio, @gffs);

GetOptions(# Required
	   'i|infile=s'           => \$infile,
	   'o|outfile=s'          => \$outfile,
	   # Options
	   't|target=s'           => \$db,
	   'k|kmerlen=i'          => \$k,
	   'r|repeat-ratio=f'     => \$ratio,
	   'filter'               => \$filter,
	   'log'                  => \$log,
	   'quiet'                => \$quiet,
	   'clean'                => \$clean,
	   'debug'                => \$debug,
	   'h|help'               => \$help,
	   'm|man'                => \$man,
);

if (!$infile || !$outfile) {
    say"\nERROR: No input or output was given.";
    usage();
    exit(1);
}

$k //= 20;
$ratio //= 0.80;
my $feat_count = 0;

my $gt = findprog('gt');

if ($filter && !$ratio) {
    warn "\nWARNING: Using a simple repeat ratio of 0.80 for filtering since one was not specified.\n";
}

# return reference of seq hash here and do tallymer search for each fasta in file
my ($seqhash, $seqreg, $seqct) = split_mfasta($infile);
my $dir = getcwd();

build_suffixarray($gt, $db);
build_index($gt, $db);

open my $out, '>', $outfile or die $!;
say $out '##gff-version 3';

for my $seqid (nsort keys %$seqreg) {
    say $out join q{ }, '##sequence-region', $seqid, '1', $seqreg->{$seqid};
}

#exit;
for my $key (nsort keys %$seqhash) {
    say "\n========> Running Tallymer Search on sequence: $key" unless $quiet;
    my $oneseq = getFh($key);
    my $matches = tallymer_search($gt, $oneseq, $db);
    
    if (exists $seqreg->{$key}) {
	$feat_count = tallymersearch2gff($seqct, $matches, $out, $key, $ratio, $feat_count);
    }
    unlink $oneseq;
    #exit;
}

#combine_gffs($gt, $outfile, \@gffs, \%seqreg);

my @files;
my $wanted  = sub { push @files, $File::Find::name
			if -f && /\.llv|\.md5|\.prf|\.tis|\.suf|\.lcp|\.ssp|\.sds|\.des|\.dna|\.esq|\.prj|\.ois|\.mer|\.mbd|\.mct/ };
my $process = sub { grep ! -d, @_ };
find({ wanted => $wanted, preprocess => $process }, $dir);
unlink @files;
#unlink @gffs;

exit;
#
# methods
#
sub combine_gffs {
    my ($gt, $outfile, $gffs, $seqreg) = @_;

    open my $out, '>', $outfile or die $!;
    say $out '##gff-version 3';

    for my $seqid (nsort keys %$seqreg) {
	say $out join q{ }, '##sequence-region', $seqid, '1', $seqreg->{$seqid};
    }

    my $featct = 0;
    for my $file (nsort @$gffs) {
	open my $in, '<', $file or die $!;
	while (my $line = <$in>) {
	    chomp $line;
	    next if $line =~ /^#/;
	    my @f = split /\t/, $line;
	    if (@f == 9) {
		$featct++;
		say $out join "\t", @f[0..7], "ID=mathematically_defined_repeat$featct;dbxref=SO:0001642";
	    }
	}
	close $in;
    }


    #system([0..5], "$gt gff3 -sort -retainids @$gffs > $outfile");

    return;
}

sub findprog {
    my ($prog) = @_;
    my $exe;

    my $gt = File::Spec->catfile($ENV{HOME}, '.tephra', 'gt', 'bin', 'gt');
    if (-e $gt && -x $gt) {
	return $gt;
    }

    my @path = split /\:|\;/, $ENV{PATH};    
    for my $p (@path) {
        my $full_path  = File::Spec->catfile($p, $prog);
	if (-e $full_path && -x $full_path) {
	    $exe = $full_path;
	}
    }
 
    if (! defined $exe) {
	say STDERR "\nERROR: $prog could not be found. Try extending your PATH to the program. Exiting.\n";
    }
    else {
	return $exe;
    }
}

sub split_mfasta {
    my ($seq) = @_;

    my $kseq = Bio::DB::HTS::Kseq->new($seq);
    my $iter = $kseq->iterator;

    my %seqregion;
    my %seq;
    my $seqct = 0;

    while (my $seqobj = $iter->next_seq()) {
	$seqct++;
	my $id = $seqobj->name;
	my $seq = $seqobj->seq;
	#next unless $id =~ /MtrunA17Chr0c01/;
	$seq{$id} = $seq;
	$seqregion{$id} = length($seq);
    }

    if ($seqct > 1) {
	say "\n========> Running Tallymer Search on $seqct sequences." unless $quiet;
    } 
   
    return (\%seq, \%seqregion, $seqct);
}

sub getFh {
    my ($key) = @_;

    my $cwd = getcwd();
    ## File::Temp->new
    my $tmpiname = $key.'_tmp_XXXX';
    my $fname = File::Temp->new( TEMPLATE => $tmpiname,
                                 DIR      => $cwd,
                                 UNLINK   => 0,
                                 SUFFIX   => '.fasta');

    open my $out, '>', $fname or die "\nERROR: Could not open file: $fname\n";

    my $seqfile = $fname->filename;
    #my $singleseq = $key.'.fasta';           # fixed bug adding extra underscore 2/10/12
    $seqhash->{$key} =~ s/.{60}\K/\n/g;      # v5.10 is required to use \K

    #open my $tmpseq, '>', $singleseq or die "\nERROR: Could not open file: $singleseq\n";
    say $out join "\n", ">".$key, $seqhash->{$key};
    close $out;

    return $seqfile;    
}

sub build_suffixarray {
    my ($gt, $db) = @_;

    my $suffix = "$gt suffixerator ".
	         "-dna ".
                 "-pl ".
                 "-suf ".
                 "-lcp ".
                 "-v ".
                 "-parts 4 ".
                 "-db $db ".
                 "-indexname $db";
    $suffix .= " 2>&1 > /dev/null" if $quiet;

    #say STDERR $suffix;

    my $exit_code;
    try {
	$exit_code = system([0..5], $suffix);
    }
    catch {
	say "ERROR: gt suffixerator failed with exit code: $exit_code. Here is the exception: $_.\n";
    };

    return;
}

sub build_index {
    my ($gt, $db) = @_;

    my $index = "$gt tallymer ".
	        "mkindex ".
                "-mersize $k ".
		"-minocc 10 ".
		"-indexname $db ".
		"-counts ".
		"-pl ".
		"-esa $db";
    $index .= " 2>&1 > /dev/null" if $quiet;

    say "\n========> Creating Tallymer index for mersize $k for sequence: $db";

    #say STDERR $index;

    my $exit_code;
    try {
	$exit_code = system([0..5], $index);
    }
    catch {
	say "ERROR: gt tallymer failed with exit code: $exit_code. Here is the exception: $_.\n";
    };

    return;
}

sub tallymer_search {
    my ($gt, $infile, $indexname) = @_;

    my ($seqfile, $seqpath, $seqext) = fileparse($infile, qr/\.[^.]*/);
    my ($indfile, $indpath, $indext) = fileparse($indexname, qr/\.[^.]*/);
    #say "========> $seqfile";
    #say "========> $indfile";
    $seqfile =~ s/\.fa.*//;
    $indfile =~ s/\.fa.*//;

    my $searchout = join "_", $seqfile, $indfile, 'tallymer-search.out';

    my $search = "$gt tallymer ".
	         "search ".
		 "-output qseqnum qpos counts sequence ".
                 "-tyr $indexname ".
                 "-q $infile ".
                 "> $searchout";

    #say "\n========> Searching $infile with $indexname" unless $quiet;
    #say "\n========> Outfile is $searchout" unless $quiet;    # The Tallymer search output. 

    #say STDERR $search;

    my $exit_code;
    try{
        $exit_code = system([0..5], $search);
    }
    catch {
	say "ERROR: gt tallymer failed with exit code: $exit_code. Here is the exception: $_.\n";
    };

    return $searchout;
}

sub tallymersearch2gff {
    my ($seqct, $matches, $out, $seqid, $ratio, $feat_count) = @_;

    open my $mers, '<', $matches or die "\nERROR: Could not open file: $matches\n";
    
    #my $count = 0;
    while (my $match = <$mers>) {
	$feat_count++;
	chomp $match;
	my ($seqnum, $offset, $mer_ct, $seq) = split /\t/, $match;
	$seq =~ s/\s+//;
	my $merlen = length($seq);

	if ($filter) {
	    my $repeatseq = filter_simple($seq, $merlen, $ratio);
	    unless (exists $repeatseq->{$seq} ) {
		printgff($mer_ct, $feat_count, $seqid, $offset, $merlen, $out);
	    }
	} 
	else {
	    printgff($mer_ct, $feat_count, $seqid, $offset, $merlen, $out);
	}
    }
    close $mers;
    unlink $matches; 

    #say STDERR $out and exit;

    return $feat_count;
}

sub filter_simple {
    my ($seq, $len, $repeat_ratio) = @_;

    my %di = ('AA' => 0, 'AC' => 0, 
	      'AG' => 0, 'AT' => 0, 
	      'CA' => 0, 'CC' => 0, 
	      'CG' => 0, 'CT' => 0, 
	      'GA' => 0, 'GC' => 0, 
	      'GG' => 0, 'GT' => 0, 
	      'TA' => 0, 'TC' => 0, 
	      'TG' => 0, 'TT' => 0);

    my %mono = ('A' => 0, 'C' => 0, 'G' => 0, 'T' => 0);

    my ($dict, $monoct, $diratio, $monoratio) = (0, 0, 0, 0);
    my %simpleseqs;

    for my $mononuc (keys %mono) {
	while ($seq =~ /$mononuc/ig) { $monoct++ };
        $monoratio = sprintf("%.2f", $monoct/$len);
	if ($monoratio >= $repeat_ratio) {
	    $simpleseqs{$seq} = $monoratio;
	}
	$monoct = 0;
    }

    for my $dinuc (keys %di) {
	while ($seq =~ /$dinuc/ig) { $dict++ };
	$diratio = sprintf("%.2f", $dict*2/$len);
	if ($diratio >= $repeat_ratio) {
	    $simpleseqs{$seq} = $diratio;
	}
	$dict = 0;
    }

    return \%simpleseqs;	    
}

sub printgff {
    my ($mer_ct, $feat_count, $seqid, $offset, $merlen, $out) = @_;

    my ($strand) = ($offset =~ /^([+-])/);
    $offset =~ s/^\+|\-//;
    #$offset = $offset > 0 ? $offset : 1;
    $offset += 1;
    my $end = $offset+$merlen;

    if ($log) {
	# may want to consider a higher level of resolution than 2 sig digs
	eval { $mer_ct = sprintf("%.2f",log($mer_ct)) }; warn $@ if $@; 
    }
    
    say $out join "\t", $seqid, "Tallymer", "mathematically_defined_repeat", $offset, $end, $mer_ct, $strand, ".",
                        join ";", "ID=mathematically_defined_repeat$feat_count","dbxref=SO:0001642";

    return;
}

sub usage {
    my $script = basename($0);
  print STDERR <<END

USAGE: $script -i contig.fas -t target.fas -k 20 -o contig_target.gff [--log] [--filter] [--clean] [-r] [-s] [-e] [-idx]

Required:
    -i|infile       :    Fasta file to search (contig or chromosome).
    -o|outfile      :    File name to write the gff to.

Options:
    -t|target       :    Fasta file of WGS reads to index.
    -k|kmerlen      :    Kmer length to use for building the index.
    -e|esa          :    Build the suffix array from the WGS reads (--target) and exit.
    -s|search       :    Just search the (--infile). Must specify an existing index.
    -r|ratio        :    Repeat ratio to use for filtering simple repeats (must be used with --filter).
    -idx|index      :    Name of the index (if used with --search option, otherwise leave ignore this option).
    --filter        :    Filter out simple repeats including di- and mononucleotides. (In testing phase)
    --log           :    Return the log number of matches instead of the raw count.
    --clean         :    Remove all the files generated by this script. This does not currently touch any of
                         the Tallymer suffix or index files. 			 
    --quiet         :    Do not print progress or program output.
	
END
}
