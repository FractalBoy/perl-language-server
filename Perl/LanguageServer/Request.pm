package Perl::LanguageServer::Request;

use strict;

use JSON;
use List::Util;

use Perl::LanguageServer::Method::TextDocument;
use Perl::LanguageServer::Method::Workspace;
use Perl::LanguageServer::Request::Base;
use Perl::LanguageServer::Request::Initialize;
use Perl::LanguageServer::Request::Initialized;
use Perl::LanguageServer::Request::CancelRequest;

sub new {
    my ($class, $request) = @_;

    my $method = $request->{method};

    if ($method eq 'initialize') {
        return Perl::LanguageServer::Request::Initialize->new($request);
    } elsif ($method eq 'initialized') {
        return Perl::LanguageServer::Request::Initialized->new($request);
    }

    return Perl::LanguageServer::Response::ServerNotInitialized->new($request)
        unless $Perl::LanguageServer::State::INITIALIZED;

    if ($method eq '$/cancelRequest') {
        return Perl::LanguageServer::Request::CancelRequest->new($request);
    }

    # create and return request classes here
    my @method = split '/', $method;

    if ($method[0] eq 'textDocument') {
        return Perl::LanguageServer::Method::TextDocument::get_request($request);
    } elsif ($method[0] eq 'workspace') {
        return Perl::LanguageServer::Method::Workspace::get_request($request);
    }

    return Perl::LanguageServer::Request::Base->new($request);
}

1;