package PLS::Server::Response;

use strict;
use warnings;

use parent 'PLS::Server::Message';

=head1 NAME

PLS::Server::Response

=head1 DESCRIPTION

This is a class representing a response to a request.
This response can originate on the server or the client.

=cut

sub new
{
    my ($class, $self) = @_;
    return bless $self, $class;
}

1;
