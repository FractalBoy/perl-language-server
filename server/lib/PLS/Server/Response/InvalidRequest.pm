package PLS::Server::Response::InvalidRequest;

use strict;
use warnings;

use parent 'PLS::Server::Response';

=head1 NAME

PLS::Server::Response::InvalidRequest

=head1 DESCRIPTION

This is an error sent from the server to the client indicating that the
client sent an invalid request.

=cut

sub new
{
    my ($class, $request) = @_;

    return
      bless {
             id    => $request->{id},
             error => {
                       code    => -32600,
                       message => 'Invalid request.'
                      }
            }, $class;
} ## end sub new

1;
