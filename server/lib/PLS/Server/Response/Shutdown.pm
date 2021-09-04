package PLS::Server::Response::Shutdown;

use strict;
use warnings;

use parent q(PLS::Server::Response);

=head1 NAME

PLS::Server::Response::Shutdown

=head1 DESCRIPTION

This is a message from the server to the client acknowledging the shutdown.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = bless {
                      id     => $request->{id},
                      result => undef
                     }, $class;

    return $self;
} ## end sub new

1;
