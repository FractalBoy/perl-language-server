use strict;
use warnings;

use Test::More tests => 9;
use FindBin;
use File::Basename;
use File::Path;
use File::Spec;
use File::Temp;
use URI;

use PLS::Parser::Document;
use PLS::Server::State;

my $text = do { local $/; <DATA> };

local $PLS::Server::State::ROOT_PATH = $FindBin::RealBin;

my $uri = URI::file->new(File::Spec->catfile($FindBin::RealBin, File::Basename::basename($0)));
PLS::Parser::Document->open_file(uri => $uri->as_string, text => $text, languageId => 'perl');

subtest 'sigil only' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 0);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 1);
    is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => 1}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'partial variable name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 1);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => 2}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$o', 'filter correct');
};

subtest 'arrow without method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 2);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 6);
    is_deeply($range, {start => {line => 0, character => 6}, end => {line => 0, character => 6}}, 'correct range');
    ok($arrow,            'arrow');
    ok(!length($package), 'no package');
    is($filter, '', 'filter correct');
};

subtest 'arrow with method name start' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 3);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 7);
    is_deeply($range, {start => {line => 0, character => 6}, end => {line => 0, character => 7}}, 'correct range');
    ok($arrow,            'arrow');
    ok(!length($package), 'no package');
    is($filter, 'm', 'filter correct');
};

subtest 'package name start, one colon' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 4);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => 5}}, 'correct range');
    ok(!$arrow, 'no arrow');
    is($package, 'File:', 'package correct');
    is($filter,  'File',  'filter correct');
};

subtest 'package name start, two colons' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 5);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 6);
    is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => 6}}, 'correct range');
    ok(!$arrow, 'no arrow');
    is($package, 'File::', 'package correct');
    is($filter,  'File',   'filter correct');
};

subtest 'class method arrow without method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 6);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 12);
    is_deeply($range, {start => {line => 0, character => 12}, end => {line => 0, character => 12}}, 'correct range');
    ok($arrow, 'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  '',           'filter correct');
};

subtest 'class method arrow with start of method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 7);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 13);
    is_deeply($range, {start => {line => 0, character => 12}, end => {line => 0, character => 13}}, 'correct range');
    ok($arrow, 'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  'c',          'filter correct');
};

subtest 'bareword function name only' => sub {

    # testing many of the various letter operators as start of function name
    my @tests = (
                 {line => 8,  filter => 'm'},
                 {line => 9,  filter => 's'},
                 {line => 10, filter => 'q'},
                 {line => 11, filter => 'qq'},
                 {line => 12, filter => 'qr'},
                 {line => 13, filter => 'qw'},
                 {line => 14, filter => 'qx'},
                 {line => 15, filter => 'func'}
                );

    plan tests => scalar @tests;

    foreach my $test (@tests)
    {
        subtest "line $test->{line}, filter $test->{filter}" => sub {
            plan tests => 5;

            my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => $test->{line});
            isa_ok($doc, 'PLS::Parser::Document');
            my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, length($test->{filter}));
            is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => length($test->{filter})}}, 'correct range');
            ok(!$arrow, 'no arrow');

            is($package, $test->{filter}, 'correct package');
            is($filter,  $test->{filter}, 'filter correct');
        }

    } ## end foreach my $test (@tests)
};

END
{
    # Clean up index created by server
    eval { File::Path::rmtree("$FindBin::RealBin/.pls_cache") };
}

__END__
$
$o
$obj->
$obj->m
File:
File::
File::Spec->
File::Spec->c
m
s
q
qq
qr
qw
qx
func
