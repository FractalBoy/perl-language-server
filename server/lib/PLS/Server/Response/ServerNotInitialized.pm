package PLS::Server::Response::ServerNotInitialized;

use strict;
use warnings;

use parent q(PLS::Server::Response);

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
