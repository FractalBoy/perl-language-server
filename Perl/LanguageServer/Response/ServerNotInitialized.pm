package Perl::LanguageServer::Response::ServerNotInitialized;
use parent q(Perl::LanguageServer::Response);

use strict;

sub new {
    my ($class) = @_;

    my %self = (
        id => $request->{id},
        error => {
            code => -32002,
            message => "server not yet initialized"
        }
    )

    return bless \%self, $class;
}

1;