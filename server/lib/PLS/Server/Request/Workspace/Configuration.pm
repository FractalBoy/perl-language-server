package PLS::Server::Request::Workspace::Configuration;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::State;

sub new
{
    my ($class) = @_;

    return bless {
        id     => undef,                       # assigned by the server
        method => 'workspace/configuration',
        params => {
                   items => [{section => 'perl.inc'}]
                  }
                 }, $class;
} ## end sub new

sub handle_response
{
    my ($self, $response) = @_;

    use Data::Dumper;
    warn Dumper $response;
    return;
}

1;
