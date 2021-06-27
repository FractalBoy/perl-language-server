package PLS::Server::Response::ServerNotInitialized;

use strict;
use warnings;

use parent q(PLS::Server::Response);

=head1 NAME

PLS::Server::Response::ServerNotInitialized

=head1 DESCRIPTION

This is an error sent from the server to the client indicating that the
client sent a request before the server was initialized.

=cut

sub new
{
    my ($class, $request) = @_;

    my %self = (
                id    => $request->{id},
                error => {
                          code    => -32002,
                          message => 'server not yet initialized'
                         }
               );

    return bless \%self, $class;
} ## end sub new

1;
