package PLS::Server::Response::Shutdown;

use strict;
use warnings;

use parent 'PLS::Server::Response';

=head1 NAME

PLS::Server::Response::Shutdown

=head1 DESCRIPTION

This is a message from the server to the client indicating that
the shutdown request has been received.

=cut

sub new
{
    my ($class, $request) = @_;

    return bless {id => $request->{id}, result => undef}, $class;
}

1;
