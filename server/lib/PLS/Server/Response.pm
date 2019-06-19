package PLS::Server::Response;

use strict;

use JSON;

use PLS::Server::Response::InitializeResult;
use PLS::Server::Response::Location;
use PLS::Server::Response::ServerNotInitialized;

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
