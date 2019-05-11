package Perl::LanguageServer::Request::TextDocument::Definition;
use parent q(Perl::LanguageServer::Request::Base);

use strict;

use Perl::LanguageServer::Response::Location;

sub service {
    my ($self) = @_;

    return Perl::LanguageServer::Response::Location->new($self);
}

1;