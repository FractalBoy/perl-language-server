package Perl::LanguageServer::Request;

use strict;

use JSON;
use List::Util;

use Perl::LanguageServer::Request::Base;
use Perl::LanguageServer::Request::Initialize;
use Perl::LanguageServer::Request::Initialized;

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

    # create and return request classes here

    return Perl::LanguageServer::Request::Base->new($request);
}

1;