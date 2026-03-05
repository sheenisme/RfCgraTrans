#!/usr/bin/perl

# Generates Makefile for each benchmark in polybench
# Expects to be executed from root folder of polybench
#
# Written by Tomofumi Yuki, 11/21 2014
#

my $GEN_CONFIG = 0;
my $TARGET_DIR = ".";

if ($#ARGV !=0 && $#ARGV != 1) {
   printf("usage perl makefile-gen.pl output-dir [-cfg]\n");
   printf("  -cfg option generates config.mk in the output-dir.\n");
   exit(1);
}



foreach my $arg (@ARGV) {
   if ($arg =~ /-cfg/) {
      $GEN_CONFIG = 1;
   } elsif (!($arg =~ /^-/)) {
      $TARGET_DIR = $arg;
   }
}


my %categories = (
   'linear_algebra/blas' => 3,
   'linear_algebra/kernels' => 3,
   'linear_algebra/solvers' => 3,
   'datamining' => 2,
   'stencils' => 2,
   'medley' => 2
);

my %extra_flags = (
   'cholesky' => '-lm',
   'gramschmidt' => '-lm',
   'correlation' => '-lm'
);

foreach $key (keys %categories) {
   my $target = $TARGET_DIR.'/'.$key;
   opendir DIR, $target or die "directory $target not found.\n";
   while (my $dir = readdir DIR) {
        next if ($dir=~'^\..*');
        next if (!(-d $target.'/'.$dir));

	my $kernel = $dir;
        my $file = $target.'/'.$dir.'/Makefile';
        my $polybenchRoot = '../'x$categories{$key};
        my $configFile = $polybenchRoot.'config.mk';
        my $utilityDir = $polybenchRoot.'utilities';

        open FILE, ">$file" or die "failed to open $file.";

print FILE << "EOF";
include $configFile

EXTRA_FLAGS=$extra_flags{$kernel}

c2mlir: $kernel.c $kernel.h
	\${VERBOSE} \${CGEIST} -o $kernel.mlir $kernel.c \${CGEIST_FLAGS} \${POLYBENCH_FLAGS} \${CGEIST_LIB} \${CGEIST_INC} -I. -I$utilityDir $utilityDir/polybench.c -include $kernel.h --function="kernel_$kernel"

$kernel: $kernel.c $kernel.h
	\${VERBOSE} \${CC} -o $kernel $kernel.c \${CFLAGS} \${POLYBENCH_FLAGS} -I. -I$utilityDir $utilityDir/polybench.c \${EXTRA_FLAGS}

run: $kernel
	\${VERBOSE} ./$kernel
   
clean:
	@ rm -f $kernel
	@ rm -f lit_tmp.c
	@ rm -f lit_tmp.mlir
	@ rm -f ${kernel}_host.c
	@ rm -f ${kernel}_kernel.mlir

distclean: clean
	@ rm -f $kernel.mlir
	@ if head -n 1 $kernel.c | grep -q 'RUN:'; then \\
		sed -i '1d' $kernel.c; \\
	fi

EOF

        close FILE;
   }


   closedir DIR;
}

if ($GEN_CONFIG) {
open FILE, '>'.$TARGET_DIR.'/config.mk';

print FILE << "EOF";
CC=gcc
CFLAGS=-O2 
POLYBENCH_FLAGS=-DPOLYBENCH_TIME -DPOLYBENCH_USE_SCALAR_LB # -DPOLYBENCH_USE_C99_PROTO

# cgeist is a binary in Polygeist to convert C to MLIR
CGEIST=cgeist
CGEIST_FLAGS=-S -memref-fullrank --raise-scf-to-affine
CGEIST_LIB=
CGEIST_INC=-I /usr/lib/gcc/x86_64-linux-gnu/12/include/
EOF

close FILE;

}

