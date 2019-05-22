#!/usr/bin/env perl

BEGIN {
    use FindBin;
    use lib "$FindBin::Bin/../../../lib";
}

use File::Spec;
use PPI;
use Test::More tests => 5;

use PLS::Parser::GoToDefinition;

use constant {
    DATA_DIR => "$FindBin::Bin/../../data"
};

sub get_document {
    my ($filename) = @_;

    open(my $fh, '<', $filename) or die;
    my $source = do { local $/; <$fh> };
    my $document = PPI::Document->new(\$source);
    $document->index_locations;
    return $document;
}

subtest 'find scalar lexical variable declaration' => sub {
    plan tests => 7;

    my $document = get_document(File::Spec->catfile(DATA_DIR, 'scalars.pl'));
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 0, 3)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 1, 0)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 4, 7)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 6, 4)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 10, 4)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 21, 10)], [21, 10]);
    $DB::signal = 1;
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 22, 4)], [21, 10]);
};

subtest 'find array lexical variable declaration' => sub {
    plan tests => 7;

    my $document = get_document(File::Spec->catfile(DATA_DIR, 'arrays.pl'));
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 0, 3)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 1, 0)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 4, 7)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 6, 4)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 7, 4)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 11, 4)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 12, 4)], [0, 3]);
};

subtest 'find hash lexical variable declaration' => sub {
    plan tests => 9;

    my $document = get_document(File::Spec->catfile(DATA_DIR, 'hashes.pl'));
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 0, 3)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 1, 0)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 4, 7)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 6, 4)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 7, 4)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 8, 4)], [4, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 12, 4)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 13, 4)], [0, 3]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 14, 4)], [0, 3]);
};

subtest 'redeclare lexical variable in same scope' => sub {
    plan tests => 5;

    my $document = get_document(File::Spec->catfile(DATA_DIR, 'scalars.pl'));
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 14, 7)], [14, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 15, 4)], [14, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 16, 7)], [16, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 17, 4)], [16, 7]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 18, 4)], [16, 7]);
};

subtest 'named subroutine declarations' => sub {
    plan tests => 12;
    
    my $document = get_document(File::Spec->catfile(DATA_DIR, 'subs.pl'));
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 0, 4)], [15, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 2, 0)], [15, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 4, 4)], [15, 8]);
    is(PLS::Parser::GoToDefinition::go_to_definition($document, 8, 0), undef);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 9, 0)], [13, 4]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 10, 0)], [13, 4]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 11, 0)], [15, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 13, 4)], [13, 4]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 14, 4)], [15, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 15, 8)], [15, 8]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 20, 0)], [13, 4]);
    is_deeply([PLS::Parser::GoToDefinition::go_to_definition($document, 21, 0)], [15, 8]);
};

=pod

TODO
----

* Global, our, state, local variables - those work differently and it's hard to figure out the rules

=cut
