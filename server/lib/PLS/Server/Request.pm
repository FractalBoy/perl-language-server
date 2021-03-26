package PLS::Server::Request;

use strict;
use warnings;

use parent 'PLS::Server::Message';

sub new
{
    my ($class, $request) = @_;

    return bless $request, $class;
} ## end sub new

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
