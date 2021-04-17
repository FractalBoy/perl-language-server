package PLS::Server::Response::DocumentSymbol;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use PLS::Parser::DocumentSymbols;

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}, result => undef}, $class;

    my $symbols = PLS::Parser::DocumentSymbols->new($request->{params}{textDocument}{uri});
    return $self if (ref $symbols ne 'PLS::Parser::DocumentSymbols');

    $self->{result} = $symbols->get_all_document_symbols();

    return $self;
} ## end sub new

1;
