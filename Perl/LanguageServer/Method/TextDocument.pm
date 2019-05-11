package Perl::LanguageServer::Method::TextDocument;

use strict;

use Perl::LanguageServer::Request::TextDocument::Definition;

sub get_request {
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'definition') {
        return Perl::LanguageServer::Request::TextDocument::Definition->new($request);
    }
}

1;