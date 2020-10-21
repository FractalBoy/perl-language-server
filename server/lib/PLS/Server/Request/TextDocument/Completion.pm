package PLS::Server::Request::TextDocument::Completion;
use parent q(PLS::Server::Request::Base);

use strict;

use PLS::Server::Response::Completion;

sub service {
    my ($self) = @_;

    return PLS::Server::Response::Completion->new($self);
}

1;
