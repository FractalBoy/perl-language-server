package Perl::LanguageServer::Method::TextDocument;

use strict;

use Data::Dumper;

sub new {
    my ($class, $method, $request) = @_;

    my %self = (
        method => $method,
        request => $request
    );

    return bless \%self, $class;
}

sub dispatch {
    my ($self) = @_;

    if ($self->{method} eq 'definition') {
        syswrite STDERR, Dumper($self->{request});
    }
}

1;