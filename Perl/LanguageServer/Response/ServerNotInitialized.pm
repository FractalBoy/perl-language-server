package Perl::LanguageServer::Response::ServerNotInitialized;

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