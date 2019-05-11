package Perl::LanguageServer::Request::Initialize;

use parent q(Perl::LanguageServer::Request::Base);

use Perl::LanguageServer::Response::InitializeResult;

sub service {
    my ($self) = @_;
    return Perl::LanguageServer::Response::InitializeResult->new($self);
}

1;