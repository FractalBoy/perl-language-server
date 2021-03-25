package PLS::Server::Request::TextDocument::Hover;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Hover;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Hover->new($self);
}

1;
