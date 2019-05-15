#!/usr/bin/env perl

use PPI;
use Test::More tests => 4;
use Data::Dumper;

use Perl::Parser::GoToDefinition;

my $source = do { local $/; <DATA> };
my $document = PPI::Document->new(\$source);
$document->index_locations;

subtest 'find scalar lexical variable declaration' => sub {
    plan tests => 5;

    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 0, 3)], [0, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 1, 0)], [0, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 4, 7)], [4, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 6, 4)], [4, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 10, 4)], [0, 3]);
};

subtest 'find array lexical variable declaration' => sub {
    plan tests => 7;

    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 13, 3)], [13, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 14, 0)], [13, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 17, 7)], [17, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 19, 4)], [17, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 20, 4)], [17, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 24, 4)], [13, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 25, 4)], [13, 3]);
};

subtest 'find hash lexical variable declaration' => sub {
    plan tests => 9;

    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 28, 3)], [28, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 29, 0)], [28, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 32, 7)], [32, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 34, 4)], [32, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 35, 4)], [32, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 36, 4)], [32, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 40, 4)], [28, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 41, 4)], [28, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 42, 4)], [28, 3]);
};

subtest 'redeclare lexical variable in same scope' => sub {
    plan tests => 5;

    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 46, 7)], [46, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 47, 4)], [46, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 48, 7)], [48, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 49, 4)], [48, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 50, 4)], [48, 7]);
};

=pod

TODO
----

* Global, our, state, local variables - those work differently and it's hard to figure out the rules

=cut

__DATA__
my $var = 1; # (0, 3) -> (0, 3)
$var = 2; # (1, 0) -> (0, 3)

sub scalar1 {
    my $var = 3; # (4, 7) -> (4, 7)

    $var = 4; # (6, 4) -> (4, 7)
}

sub scalar2 {
    $var = 5; # (10, 4) -> (0, 3)
}

my @array = (1, 2, 3); # (13, 3) -> (13, 3)
@array = (1, 2); # (14, 0) -> (13, 3)

sub array1 {
    my @array = (2, 3, 4); # (17, 7) -> (17, 7)

    @array = (1); # (19, 4) -> (17, 7)
    $array[0] = 1; # (20, 4) -> (17, 7)
}

sub array2 {
    @array = (4); # (24, 4) -> (13, 3)
    $array[2] = 2; # (25, 4) -> (13, 3)
}

my %hash = (a => 1, b => 2); # (28, 3) -> (28, 3)
%hash = (a => 1); # (29, 0) -> (28, 3)

sub hash1 {
    my %hash = (a => 1, b => 2, c => 3); # (32, 7) -> (32, 7)

    %hash = (d => 4); # (34, 4) -> (32, 7)
    $hash{a} = 2; # (35, 4) -> (32, 7)
    $hash{'a'} = 3; # (36, 4) -> (32, 7)
}

sub hash2 {
    %hash = (d => 4); # (40, 4) -> (28, 3)
    $hash{b} = 4; # (41, 4) -> (28, 3)
    $hash{'c'} = 5; # (42, 4) -> (28, 3)
}

sub redeclare {
    my $scalar = 1; # (46, 7) -> (46, 7)
    $scalar = 2; # (47, 4) -> (46, 7)
    my $scalar = 3; (48, 7) -> (48, 7)
    $scalar = 4; (49, 4) -> (48, 7)
    $scalar = 5; (50, 4) -> (48, 7)
}