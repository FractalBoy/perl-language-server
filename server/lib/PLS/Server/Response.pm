package PLS::Server::Response;

use strict;
use warnings;

use parent 'PLS::Server::Message';

sub new
{
    my ($class, $self) = @_;
    return bless $self, $class;
}

1;
