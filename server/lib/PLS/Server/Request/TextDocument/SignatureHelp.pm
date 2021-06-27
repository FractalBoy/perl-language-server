package PLS::Server::Request::TextDocument::SignatureHelp;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::SignatureHelp;

=head1 NAME

PLS::Server::Request::TextDocument::SignatureHelp

=head1 DESCRIPTION

This is a message from the client to the server requesting
information on the parameters of a function at a given location.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::SignatureHelp->new($self);
}

1;
