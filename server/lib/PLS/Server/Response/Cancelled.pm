package PLS::Server::Response::Cancelled;

use strict;
use warnings;

use parent q(PLS::Server::Response);

=head1 NAME

PLS::Server::Response::Cancelled

=head1 DESCRIPTION

This is a message from the server to the client indicating that
a request has been cancelled.

=cut

sub new
{
    my ($class, %args) = @_;

    return
      bless {
             id    => $args{id},
             error => {code => -32800, message => 'Request cancelled.'}
            }, $class;
} ## end sub new

1;
