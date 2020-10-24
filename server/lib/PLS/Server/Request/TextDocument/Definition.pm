package PLS::Server::Request::TextDocument::Definition;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use PLS::Server::Response::Location;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Location->new($self);
}

1;
