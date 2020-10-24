package PLS::Server::Response;

use strict;
use warnings;

use parent 'PLS::Server::Message';
use JSON;

use PLS::Server::Response::InitializeResult;
use PLS::Server::Response::Location;
use PLS::Server::Response::ServerNotInitialized;

sub new
{
    my ($class, $self) = @_;
    return bless $self, $class;
}

1;
