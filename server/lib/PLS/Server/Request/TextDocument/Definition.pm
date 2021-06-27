package PLS::Server::Request::TextDocument::Definition;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Location;

=head1 NAME

PLS::Server::Request::TextDocument::Definition

=head1 DESCRIPTION

This is a message from the client to the server requesting the
definition location of a particular symbol at a given location.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Location->new($self);
}

1;
