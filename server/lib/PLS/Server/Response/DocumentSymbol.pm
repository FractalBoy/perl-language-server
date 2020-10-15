package PLS::Server::Response::DocumentSymbol;
use parent q(PLS::Server::Response);

use strict;

use PLS::Parser::DocumentSymbols;

sub new {
    my ($class, $request) = @_;

    my $results = PLS::Parser::DocumentSymbols::get_all_document_symbols($request->{params}{textDocument}{uri});

    my %self = (
        id => $request->{id},
        result => $results
    );

    return bless \%self, $class;
}

1;
