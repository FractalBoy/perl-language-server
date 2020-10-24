package PLS::Server::Request::TextDocument::DocumentSymbol;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use PLS::Server::Response::DocumentSymbol;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::DocumentSymbol->new($self);
}

1;
