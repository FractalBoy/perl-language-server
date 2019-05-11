package Perl::LanguageServer::Request::CancelRequest;
use parent q(Perl::LanguageServer::Request::Base);

use strict;

sub service {
    my ($self) = @_;

    # right now, we'll just add this id to the list of cancelled ids.
    # we don't yet have the ability to cancel a request in flight.
    # according to the specification, the server is still supposed to send
    # a response even if it was canceled.
    push @Perl::LanguageServer::State::CANCELED, $self->{params}{id};
    return undef;
}

1;