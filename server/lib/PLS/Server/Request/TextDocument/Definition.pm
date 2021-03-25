package PLS::Server::Request::TextDocument::Definition;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Location;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Location->new($self);
}

1;
