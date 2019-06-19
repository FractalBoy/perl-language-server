use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'PLS',
    VERSION_FROM => 'lib/PLS.pm',
    EXE_FILES => ['bin/pls'],
    PREREQ_PM => {
        'AnyEvent' => 7.15,
        'Coro' => 6.54,
        'Coro::AnyEvent' => 6.54,
        'Coro::Handle' => 6.54,
        'File::Spec' => 3.67,
        'JSON' => 4.02,
        'List::Util' => 1.4602,
        'Perl::Critic::Utils' => 1.132,
        'PPI' => 1.264,
        'PPI::Find' => 1.264,
        'Scalar::Util' => 1.4602,
        'Test::More' => 1.302073,
        'URI' => 1.76
    },
    test => { TESTS => 't/PLS/Parser/GoToDefinition.t' }
);
