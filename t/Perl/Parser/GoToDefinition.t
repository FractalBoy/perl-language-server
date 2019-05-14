#!/usr/bin/env perl

use PPI;
use Test::More tests => 3;
use Data::Dumper;

use Perl::Parser::GoToDefinition;

my $source = do { local $/; <DATA> };
my $document = PPI::Document->new(\$source);
$document->index_locations;

subtest 'find scalar declaration' => sub {
    plan tests => 5;

    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 0, 3)], [0, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 1, 0)], [0, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 4, 7)], [4, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 6, 4)], [4, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 10, 4)], [0, 3]);
};

subtest 'find array declaration' => sub {
    plan tests => 7;

    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 13, 3)], [13, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 14, 0)], [13, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 17, 7)], [17, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 19, 4)], [17, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 20, 4)], [17, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 24, 4)], [13, 3]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 25, 4)], [13, 3]);
};

subtest 'find global declaration' => sub {
    plan tests => 5;

    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 28, 0)], [28, 0]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 31, 4)], [28, 0]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 32, 7)], [32, 7]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 33, 4)], [33, 4]);
    is_deeply([Perl::Parser::GoToDefinition::go_to_definition($document, 34, 4)], [33, 4]);
};

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

$global = 1; # (28, 0) -> (28, 0)

sub global {
    $global = 2; # (31, 4) -> (28, 0)
    my $global = 1; # (32, 7) -> (32, 7)
    $global2 = 1; # (33, 4) -> (33, 4)
    $global2 = 2; # (34, 4) -> (33, 4)
}