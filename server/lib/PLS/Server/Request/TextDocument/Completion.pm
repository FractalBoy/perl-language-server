package PLS::Server::Request::TextDocument::Completion;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Completion;

=head1 NAME

PLS::Server::Request::TextDocument::Completion

=head1 DESCRIPTION

This is a message from the client to the server requesting
that the server provide a list of completion items for the
current cursor position.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Completion->new($self);
}

1;
