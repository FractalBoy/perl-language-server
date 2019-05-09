package Perl::LanguageServer::Response;

use JSON;

sub send {
    my ($self, $request, $fh) = @_;

    my %content = (
        jsonrpc => '2.0',
        id => $request->{content}{id},
        result => $self->{result},
#        error => $self->{error}
    );

    my $json = encode_json \%content;
    my $size = length($json);
    syswrite $fh, "Content-Length: $size\r\n\r\n";
    syswrite $fh, $json, $size;
}

1;