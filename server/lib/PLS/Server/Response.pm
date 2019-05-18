package PLS::Server::Response;

use strict;

use JSON;

sub serialize {
    my ($self) = @_;

    my %content = (
        jsonrpc => '2.0',
        %{$self}
    );

    my $json = encode_json \%content;
    return $json;
}

1;
