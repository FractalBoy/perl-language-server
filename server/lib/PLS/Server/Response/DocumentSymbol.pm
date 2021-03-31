package PLS::Server::Response::DocumentSymbol;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use PLS::Parser::DocumentSymbols;

sub new
{
    my ($class, $request) = @_;

    my $symbols = PLS::Parser::DocumentSymbols->new($request->{params}{textDocument}{uri});
    my $results = $symbols->get_all_document_symbols();

    my %self = (
                id     => $request->{id},
                result => $results
               );

    return bless \%self, $class;
} ## end sub new

1;
