package PLS::Server::Request::TextDocument::Hover;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Hover;

=head1 NAME

PLS::Server::Request::TextDocument::Hover

=head1 DESCRIPTION

This is a message from the client to the server requesting
hover information at a particular location.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Hover->new($self);
}

1;
