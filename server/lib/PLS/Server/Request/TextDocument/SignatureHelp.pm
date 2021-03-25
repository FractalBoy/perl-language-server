package PLS::Server::Request::TextDocument::SignatureHelp;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::SignatureHelp;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::SignatureHelp->new($self);
}

1;
