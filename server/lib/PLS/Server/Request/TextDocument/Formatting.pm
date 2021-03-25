package PLS::Server::Request::TextDocument::Formatting;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Formatting;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Formatting->new($self);
}

1;
