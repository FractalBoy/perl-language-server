package PLS::Server::Request::TextDocument::DocumentSymbol;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::DocumentSymbol;

=head1 NAME

PLS::Server::Response::DocumentSymbol

=head1 DESCRIPTION

This is a message from the client to the server requesting
a list of all symbols in the current document.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::DocumentSymbol->new($self);
}

1;
