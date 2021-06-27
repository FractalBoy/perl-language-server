package PLS::Server::Request::TextDocument::Formatting;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Formatting;

=head1 NAME

PLS::Server::Request::TextDocument::Formatting

=head1 DESCRIPTION

This is a message from the client to the server requesting that
the server format the current document.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Formatting->new($self);
}

1;
