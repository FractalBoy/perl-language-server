#!perl

use strict;
use warnings;

use Test::More tests => 38;
use FindBin;
use File::Basename;
use File::Path;
use File::Spec;
use File::Temp;
use URI;

use PLS::Parser::Document;
use PLS::Server::State;

my $text = do { local $/; <DATA> };

# Cache workspace folders
PLS::Parser::Index->new(workspace_folders => [$FindBin::RealBin]);

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

subtest 'arrow with full method name chained to blank method' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 4);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 14);
    is_deeply($range, {start => {line => 0, character => 14}, end => {line => 0, character => 14}}, 'correct range');
    ok($arrow,            'arrow');
    ok(!length($package), 'no package');
    is($filter, '', 'filter correct');
};

subtest 'arrow with full method name chained to method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 5);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 14);
    is_deeply($range, {start => {line => 0, character => 14}, end => {line => 0, character => 15}}, 'correct range');
    ok($arrow,            'arrow');
    ok(!length($package), 'no package');
    is($filter, 'm', 'filter correct');
};

subtest 'package name start, one colon' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 6);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => 5}}, 'correct range');
    ok(!$arrow, 'no arrow');
    is($package, 'File:', 'package correct');
    is($filter,  'File',  'filter correct');
};

subtest 'package name start, two colons' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 7);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 6);
    is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => 6}}, 'correct range');
    ok(!$arrow, 'no arrow');
    is($package, 'File::', 'package correct');
    is($filter,  'File',   'filter correct');
};

subtest 'class method arrow without method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 8);
    isa_ok($doc, 'PLS::Parser::Document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 12);
    is_deeply($range, {start => {line => 0, character => 12}, end => {line => 0, character => 12}}, 'correct range');
    ok($arrow, 'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  '',           'filter correct');
};

subtest 'class method arrow with start of method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 9);
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
                 {line => 12, filter => 'm'},
                 {line => 13, filter => 's'},
                 {line => 14, filter => 'q'},
                 {line => 15, filter => 'qq'},
                 {line => 16, filter => 'qr'},
                 {line => 17, filter => 'qw'},
                 {line => 18, filter => 'qx'},
                 {line => 19, filter => 'func'}
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

subtest 'start of package inside function parentheses' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 20);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 11);
    is_deeply($range, {start => {line => 0, character => 5}, end => {line => 0, character => 11}}, 'correct range');
    ok(!$arrow, 'no arrow');
    is($package, 'File::', 'package correct');
    is($filter,  'File',   'filter correct');
};

subtest 'start of package inside method parentheses' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 21);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 19);
    is_deeply($range, {start => {line => 0, character => 13}, end => {line => 0, character => 19}}, 'correct range');
    ok(!$arrow, 'no arrow');
    is($package, 'File::', 'package correct');
    is($filter,  'File',   'filter correct');
};

subtest 'class method arrow without method name inside method parentheses' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 22);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 25);
    is_deeply($range, {start => {line => 0, character => 25}, end => {line => 0, character => 25}}, 'correct range');
    ok($arrow, 'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  '',           'filter correct');
};

subtest 'class method arrow with start of method name inside method parentheses' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 23);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 26);
    is_deeply($range, {start => {line => 0, character => 25}, end => {line => 0, character => 26}}, 'correct range');
    ok($arrow, 'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  'c',          'filter correct');
};

subtest 'variable typed before another variable' => sub {
    plan tests => 4;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 24);
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => 2}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

subtest 'only sigil before arrow' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 25);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 1);
    is_deeply($range, {start => {line => 0, character => 0}, end => {line => 0, character => 1}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');

};

subtest 'only sigil before close paren' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 26);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is_deeply($range, {start => {line => 0, character => 1}, end => {line => 0, character => 2}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'only sigil before close curly brace' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 27);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is_deeply($range, {start => {line => 0, character => 1}, end => {line => 0, character => 2}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'only sigil before comma' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 28);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is_deeply($range, {start => {line => 0, character => 1}, end => {line => 0, character => 2}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'two arrows in a row' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 29);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 6);
    is_deeply($range, {start => {line => 0, character => 6}, end => {line => 0, character => 6}}, 'correct range');
    ok($arrow,            'arrow');
    ok(!length($package), 'no package');
    is($filter, '', 'filter correct');
};

subtest 'fill method name between arrows' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 30);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 7);
    is_deeply($range, {start => {line => 0, character => 6}, end => {line => 0, character => 7}}, 'correct range');
    ok($arrow,            'arrow');
    ok(!length($package), 'no package');
    is($filter, 'm', 'filter correct');
};

subtest 'sigil between double quotes' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 31);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is_deeply($range, {start => {line => 0, character => 1}, end => {line => 0, character => 2}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'variable between double quotes' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 32);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 3);
    is_deeply($range, {start => {line => 0, character => 1}, end => {line => 0, character => 3}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

subtest 'sigil in qr' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 33);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is_deeply($range, {start => {line => 0, character => 3}, end => {line => 0, character => 4}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'variable in qr' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 34);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is_deeply($range, {start => {line => 0, character => 3}, end => {line => 0, character => 5}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

subtest 'sigil in qx' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 35);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is_deeply($range, {start => {line => 0, character => 3}, end => {line => 0, character => 4}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'variable in qx' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 36);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is_deeply($range, {start => {line => 0, character => 3}, end => {line => 0, character => 5}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

subtest 'sigil in qq' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 37);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is_deeply($range, {start => {line => 0, character => 3}, end => {line => 0, character => 4}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'variable in qq' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 38);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is_deeply($range, {start => {line => 0, character => 3}, end => {line => 0, character => 5}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

subtest 'sigil in s' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 39);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 3);
    is_deeply($range, {start => {line => 0, character => 2}, end => {line => 0, character => 3}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'variable in s' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 40);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is_deeply($range, {start => {line => 0, character => 2}, end => {line => 0, character => 4}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

subtest 'sigil in m' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 41);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 3);
    is_deeply($range, {start => {line => 0, character => 2}, end => {line => 0, character => 3}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'variable in m' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 42);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is_deeply($range, {start => {line => 0, character => 2}, end => {line => 0, character => 4}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

subtest 'sigil in y' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 43);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 3);
    is_deeply($range, {start => {line => 0, character => 2}, end => {line => 0, character => 3}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'variable in y' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 44);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is_deeply($range, {start => {line => 0, character => 2}, end => {line => 0, character => 4}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

subtest 'sigil in tr' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 45);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is_deeply($range, {start => {line => 0, character => 3}, end => {line => 0, character => 4}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$', 'filter correct');
};

subtest 'variable in tr' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 46);
    isa_ok($doc, 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is_deeply($range, {start => {line => 0, character => 3}, end => {line => 0, character => 5}}, 'correct range');
    ok(!$arrow,           'no arrow');
    ok(!length($package), 'no package');
    is($filter, '$x', 'filter correct');
};

__END__
$
$o
$obj->
$obj->m
$obj->method->
$obj->method->m
File:
File::
File::Spec->
File::Spec->c
File::Spec->catfile->
File::Spec->catfile->m
m
s
q
qq
qr
qw
qx
func
func(File::)
$obj->method(File::)
$obj->method(File::Spec->)
$obj->method(File::Spec->c)
$x$obj
$->method
($)
{$}
($,$y)
$obj->->method()
$obj->m->method()
"$"
"$x"
qr/$/
qr/$x/
qx($)
qx($x)
qq{$}
qq{$x}
s/$/
s/$x/
m<$>
m<$x>
y/$/
y/$x/
tr[$]
tr[$x]
