package PLS::Server::Request::TextDocument::RangeFormatting;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::RangeFormatting;

=head1 NAME

PLS::Server::Request::TextDocument::RangeFormatting

=head1 DESCRIPTION

This is a message from the client to the server requesting that
the server format a section of the current document.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::RangeFormatting->new($self);
}

1;
