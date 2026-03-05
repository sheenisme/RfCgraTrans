#!/usr/bin/perl

# Visits every directory, calls make, and then executes the benchmark
# (Designed for making sure every kernel compiles/runs after modifications)
#
# Written by Tomofumi Yuki, 01/15 2015
#

my $TARGET_DIR = ".";
my $OPTION = "all";
my $OUTFILE = "";

my $argc = scalar @ARGV;
if ($argc < 1 || $argc > 3) {
   printf("usage: perl run-all.pl target-dir [make-option=all] [output-file]\n");
   exit(1);
}

if ($argc >= 1) {
   $TARGET_DIR = $ARGV[0];
}
if ($argc >= 2) {
   $OPTION = $ARGV[1];
}
if ($argc == 3) {
   $OUTFILE = $ARGV[2];
}

# Use benchmark_list and benchmark_skipped to determine test cases
my $LIST_FILE = $TARGET_DIR.'/utilities/benchmark_list';
my $SKIP_FILE = $TARGET_DIR.'/utilities/benchmark_skipped';

# Read skip list (ignore empty/comment lines)
my %skip = ();
if (open my $sf, '<', $SKIP_FILE) {
   while (my $line = <$sf>) {
      chomp $line;
      next if ($line =~ /^\s*$/);
      next if ($line =~ /^\s*#/);
      $skip{$line} = 1;
   }
   close $sf;
}

# Iterate benchmark_list (ignore empty/comment lines) and skip entries in %skip
open my $lf, '<', $LIST_FILE or die "file $LIST_FILE not found.\n";
while (my $bench = <$lf>) {
   chomp $bench;
   next if ($bench =~ /^\s*$/);
   next if ($bench =~ /^\s*#/);

   # bench looks like ./path/to/kernel/file.c; take its directory to run make
   my $benchdir = $bench;
   $benchdir =~ s|/[^/]+$||; # dirname
   my $targetDir = $TARGET_DIR.'/'.$benchdir;
   my $command = "";
   
   if (exists $skip{$bench}) {
      # If the benchmark is in the skip list, skip it
      $command = "echo Skipping $benchdir";
   } else {
      # Otherwise, run make with the specified option
      # Redirect stderr to OUTFILE if specified
      $command = "cd $targetDir; make distclean; make $OPTION;";
      $command .= " 2>> $OUTFILE" if ($OUTFILE ne '');
      print($command."\n");
   }

   system($command);
}
close $lf;
