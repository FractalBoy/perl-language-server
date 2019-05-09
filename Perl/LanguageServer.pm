package Perl::LanguageServer;

use strict;

use Data::Dumper;
use JSON;

use Perl::LanguageServer::Request;
use Perl::LanguageServer::Response;
use Perl::LanguageServer::Response::InitializeResult;
use Perl::LanguageServer::Methods::Workspace;

sub new {
    my ($class, $readfh, $writefh) = @_;

    my $fh = select($readfh); $| = 1; select($fh);
    
    my %self = (
        readfh => $readfh || \*STDIN,
        writefh => $writefh || \*STDOUT,
        initialized => 0
    );

    return bless \%self, $class;
}

sub continue {
    my ($self) = @_;

    return !eof($self->{readfh});
}

sub get_request {
    my ($self) = @_;

    my %headers;
    my $readfh = $self->{readfh};
    
    local $/ = "\r\n";
    while (my $buffer = <$readfh>) {
        die "error while reading headers" unless $buffer;
        last if $buffer eq "\r\n";
        chomp($buffer);
        my ($field, $value) = split /: /, $buffer;
        $headers{$field} = $value;
    }

    my $size = $headers{'Content-Length'};
    die 'no Content-Length header provided' unless $size;

    my $raw;
    my $length = read($readfh, $raw, $size);
    die 'content length does not match header' unless $length == $size;

    my $content = decode_json $raw;

    return Perl::LanguageServer::Request->new(
        headers => \%headers,
        content => $content
    );
}

sub handle_request {
    my ($self, $request) = @_;

    # if we're not initialized yet, send an error
    unless ($self->{initialized}) {
        # send error
        return 0;
    }

    my ($type, $method) = split '/', $request->{content}{method};

    # implement the rest of the methods here
    if ($type eq 'workspace') {
        my $workspace = Perl::LanguageServer::Methods::Workspace->new($method, $request);
        $workspace->dispatch;
    }

    return 1;
}

sub initialize {
    my ($self) = @_;

    my $request = $self->get_request;

    unless ($request->{content}{method} eq 'initialize') {
        # send error
        return 0;
    }
        
    my $response = Perl::LanguageServer::Response::InitializeResult->new;
    $response->send($request, $self->{writefh});

    $request = $self->get_request;

    unless ($request->{content}{method} eq 'initialized') {
        # send error
        return 0;
    }

    $self->{initialized} = 1;
    return 1;
}

sub run {
    my $server = Perl::LanguageServer->new;

    for (my $tries = 0; $tries < 5; $tries++) {
        last if $server->initialize;
    }

    while ($server->continue) {
        my $request = $server->get_request;
        return unless $server->handle_request($request);
   }
}

1;