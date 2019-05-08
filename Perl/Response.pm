package Perl::Response;

use JSON;

sub serialize {
    my ($self) = @_;

    my %content = (
        id => Perl::LanguageServer::next_request_id(),
        result => $self->{result},
        error => $self->{error}
    )

    return encode_json \%content;
}