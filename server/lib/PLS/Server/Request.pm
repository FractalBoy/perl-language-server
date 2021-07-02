package PLS::Server::Request;

use strict;
use warnings;

use parent 'PLS::Server::Message';

=head1 NAME

PLS::Server::Request

=head1 DESCRIPTION

This class represents a request. The request can originate on the server or the client.
If the request originates on the server and a response is expected,
the C<handle_response> method should be implemented.

=cut

sub new
{
    my ($class, $request) = @_;

    return bless $request, $class;
}

sub service
{
    my ($self, $server) = @_;
    return;
}

sub handle_response
{
    my ($self, $response, $server) = @_;

    return;
}

1;
