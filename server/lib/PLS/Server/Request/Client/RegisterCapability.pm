package PLS::Server::Request::Client::RegisterCapability;

use strict;
use warnings;

use parent 'PLS::Server::Request';

=head1 NAME

PLS::Server::Request::Client::RegisterCapability

=head1 DESCRIPTION

This is a message from the server to the client requesting that
a new capability be registered.

This request must be sent for capabilities that cannot be registered for statically.

=cut

sub new
{
    my ($class, $registrations) = @_;

    my %self = (
                method => 'client/registerCapability',
                params => {
                           registrations => $registrations
                          }
               );

    return bless \%self, $class;
} ## end sub new

1;
