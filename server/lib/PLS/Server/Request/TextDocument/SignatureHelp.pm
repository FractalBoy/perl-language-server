package PLS::Server::Request::TextDocument::SignatureHelp;
use parent q(PLS::Server::Request::Base);

use strict;

use PLS::Server::Response::SignatureHelp;

sub service {
    my ($self) = @_;

    return PLS::Server::Response::SignatureHelp->new($self);
}

1;
