package Perl::Request;

use strict;

use JSON;

sub new {
    my ($class, $fh) = @_;

    die unless $fh;

    my %self = ( fh => $fh );
    my $self = bless \%self, $class;
    
    $self->{headers} = $self->getHeaders();
    $self->{content} = $self->getContent();

    return $self;
}

sub getHeaders {
    my ($self) = @_;

    my %headers;
    my $fh = $self->{fh};
    
    while (my $buffer = <$fh>) {
        die "error while reading headers" unless $buffer;
        last if $buffer eq "\r\n";
        $buffer =~ s/^\s+|\s+$//g;
        my ($field, $value) = split /: /, $buffer;
        $headers{$field} = $value;
    }

    return \%headers;
}

sub getContent {
    my ($self) = @_;

    my $size = $self->{headers}{'Content-Length'};
    die 'no Content-Length header provided' unless $size;

    my $raw;
    my $length = read($self->{fh}, $raw, $size);
    die 'content length does not match header' unless $length == $size;

    my $content = decode_json $raw;
    return $content;
}

1;