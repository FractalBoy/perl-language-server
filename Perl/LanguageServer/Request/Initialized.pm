package Perl::LanguageServer::Request::Initialized;

use parent q{Perl::LanguageServer::Request::Base};

use Perl::LanguageServer::State;

sub service {
    $Perl::LanguageServer::State::INITIALIZED = 1;
    return undef;
}

1;