#!/usr/bin/env perl

use PPI;
use Test::More tests => 2;
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
}

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