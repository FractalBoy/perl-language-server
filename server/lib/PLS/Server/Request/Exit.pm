package PLS::Server::Request::Exit;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Scalar::Util qw(blessed);

=head1 NAME

PLS::Server::Request::Exit

=head1 DESCRIPTION

This is a notification message from the client to the server requesting
that the server exits.

=cut

sub service
{
    exit 1;
} ## end sub service

1;
