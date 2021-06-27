use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'PLS',
    VERSION_FROM => 'lib/PLS.pm',
    EXE_FILES => [ 'bin/pls' ],
    MIN_PERL_VERSION => 5.026001,
    PREREQ_PM => {
        'AnyEvent' => 7.15,
        'Coro' => 6.54,
        'Path::Tiny' => 0.114,
        'Perl::Critic' => 1.138,
        'Perl::Tidy' => 20210402,
        'Pod::Find' => 1.63,
        'Pod::Markdown' => 3.200,
        'PPI' => 1.264,
        'PPR' => 0.000028,
        'URI' => 1.76
    },
    TESTS => 't/*.t'
);
