package PLS::Server::Request::TextDocument::Formatting;
use parent q(PLS::Server::Request::Base);

use strict;

use PLS::Server::Response::Formatting;

sub service {
    my ($self) = @_;

    return PLS::Server::Response::Formatting->new($self);
}

1;
