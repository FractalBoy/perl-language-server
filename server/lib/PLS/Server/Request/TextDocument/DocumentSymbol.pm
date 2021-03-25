package PLS::Server::Request::TextDocument::DocumentSymbol;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::DocumentSymbol;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::DocumentSymbol->new($self);
}

1;
