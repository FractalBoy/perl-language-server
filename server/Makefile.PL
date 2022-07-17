use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
              NAME             => 'PLS',
              VERSION_FROM     => 'lib/PLS.pm',
              ABSTRACT_FROM    => 'lib/PLS.pm',
              EXE_FILES        => ['bin/pls'],
              LICENSE          => 'perl_5',
              MIN_PERL_VERSION => 5.026000,
              PREREQ_PM        => {
                            'IO::Async'     => 0.79,
                            'Future'        => 0.47,
                            'Future::Utils' => 0.47,
                            'Future::Queue' => 0.47,
                            'Path::Tiny'    => 0.114,
                            'Perl::Critic'  => 1.140,
                            'Perl::Tidy'    => 20210402,
                            'Pod::Markdown' => 3.200,
                            'PPI'           => 1.264,
                            'PPR'           => 0.000028,
                            'URI'           => 1.76
                           },
              test => {TESTS => 't/*.t'},
              (
               eval { ExtUtils::MakeMaker->VERSION(6.46) }
               ? (
                  META_MERGE => {
                                 'meta-spec' => {version => 2},
                                 resources   => {
                                               repository => {
                                                              type => 'git',
                                                              url  => 'https://github.com/FractalBoy/perl-language-server.git',
                                                              web  => 'https://github.com/FractalBoy/perl-language-server',
                                                             },
                                              }
                                }
                 )
               : ()
              )
             );
