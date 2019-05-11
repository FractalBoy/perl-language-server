package Perl::LanguageServer::Method::Workspace;

use strict;

use Perl::LanguageServer::Request::Workspace::DidChangeConfiguration;

sub get_request {
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'didChangeConfiguration') {
        return Perl::LanguageServer::Request::Workspace::DidChangeConfiguration->new($request);
    }
}

1;