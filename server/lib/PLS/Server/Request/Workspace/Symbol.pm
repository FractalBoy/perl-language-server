package PLS::Server::Request::Workspace::Symbol;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::WorkspaceSymbols;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::WorkspaceSymbols->new($self);
}

1;
