package PLS::Server::Request::Exit;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::State;

=head1 NAME

PLS::Server::Request::Exit

=head1 DESCRIPTION

This is a notification message from the client to the server requesting
that the server exits.

=cut

sub service
{
    my ($self, $server) = @_;

    my $exit_code = $PLS::Server::State::SHUTDOWN ? 0 : 1;
    $server->stop($exit_code);

    return;
} ## end sub service

1;
