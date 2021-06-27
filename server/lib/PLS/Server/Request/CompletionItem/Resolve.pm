package PLS::Server::Request::CompletionItem::Resolve;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Resolve;

=head1 NAME

PLS::Server::Request::CompletionItem::Resolve

=head1 DESCRIPTION

This is a message from the client to the server requesting that
a completion item be resolved with additional information.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Resolve->new($self);
}

1;
