package PLS::Server::Response::ServerNotInitialized;
use parent q(PLS::Server::Response);

use strict;

sub new {
    my ($class, $request) = @_;

    my %self = (
        id => $request->{id},
        error => {
            code => -32002,
            message => "server not yet initialized"
        }
    );

    return bless \%self, $class;
}

1;
