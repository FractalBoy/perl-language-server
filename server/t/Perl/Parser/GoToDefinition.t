#!/usr/bin/env perl

BEGIN {
    use FindBin;
    use lib "$FindBin::Bin/../../../lib";
}

use PPI;
use Test::More tests => 5;
use Data::Dumper;

use PLS::Parser::GoToDefinition;

my $source = do { local $/; <DATA> };
my $document = PPI::Document->new(\$source);
$document->index_locations;

subtest 'find scalar lexical variable declaration' => sub {
    plan tests => 5;

    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 0, 3)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 1, 0)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 4, 7)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 6, 4)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 10, 4)], [0, 3]);
};

subtest 'find array lexical variable declaration' => sub {
    plan tests => 7;

    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 13, 3)], [13, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 14, 0)], [13, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 17, 7)], [17, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 19, 4)], [17, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 20, 4)], [17, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 24, 4)], [13, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 25, 4)], [13, 3]);
};

subtest 'find hash lexical variable declaration' => sub {
    plan tests => 9;

    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 28, 3)], [28, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 29, 0)], [28, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 32, 7)], [32, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 34, 4)], [32, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 35, 4)], [32, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 36, 4)], [32, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 40, 4)], [28, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 41, 4)], [28, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 42, 4)], [28, 3]);
};

subtest 'redeclare lexical variable in same scope' => sub {
    plan tests => 5;

    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 46, 7)], [46, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 47, 4)], [46, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 48, 7)], [48, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 49, 4)], [48, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 50, 4)], [48, 7]);
};

subtest 'named subroutine declarations' => sub {
    plan tests => 10;
    
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 53, 4)], [66, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 55, 0)], [66, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 57, 4)], [66, 8]);
    is(PLS::Parser::GoToDefinition::go_to_definition($document, 61, 0), undef);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 62, 0)], [66, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 64, 4)], [64, 4]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 65, 4)], [66, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 66, 8)], [66, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 71, 0)], [64, 4]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 72, 0)], [66, 8]);
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

sub subroutine; (53, 4) -> (66, 8)

subroutine; (55, 0) -> (66, 8)

sub subroutine { (57, 4) -> (66, 8)
    ...
}

subroutine2; (61, 0) -> (????)
subroutine; (62, 0) -> (66, 8)

sub subroutine2 { (64, 4) -> (64, 4)
    subroutine; (65, 4) -> (66, 8)
    sub subroutine { (66, 8) -> (66, 8)
        ...
    }
}

subroutine2; (71, 0) -> (64, 4)
subroutine; (72, 0) -> (66, 8)
