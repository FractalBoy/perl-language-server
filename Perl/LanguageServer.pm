package Perl::LanguageServer;

use strict;

use Data::Dumper;
use IO::Handle;
use IO::Select;
use JSON;
use Symbol;

use Perl::LanguageServer::Request;
use Perl::LanguageServer::Response;
use Perl::LanguageServer::Response::InitializeResult;
use Perl::LanguageServer::Method::Workspace;
use Perl::LanguageServer::Method::TextDocument;

sub new {
    my ($class, $readfh, $writefh) = @_;

    my %self = (
        readfh => $readfh || \*STDIN,
        writefh => $writefh || \*STDOUT,
        initialized => 0
    );

    return bless \%self, $class;
}

sub get_request {
    my ($self) = @_;

    my %headers;
    my $readfh = $self->{readfh};
    my $line; 
    while (sysread($readfh, my $buffer, 1)) {
        return 0 unless length($buffer);
        $line .= $buffer;
        last if $line eq "\r\n";
        next unless $line =~ /\r\n$/;
        $line =~ s/^\s+|\s+$//g;
        my ($field, $value) = split /: /, $line;
        $headers{$field} = $value;
        $line = '';
        sleep(1); # this sleep really helps, not sure why.
    }

    my $size = $headers{'Content-Length'};
    die 'no Content-Length header provided' unless $size;

    my $length = sysread($readfh, my $raw, $size);
    die 'content length does not match header' unless $length == $size;

    my $content = decode_json $raw;

    return (1, Perl::LanguageServer::Request->new(
        headers => \%headers,
        content => $content
    ));
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
        my $workspace = Perl::LanguageServer::Method::Workspace->new($method, $request);
        $workspace->dispatch;
    } elsif ($type eq 'textDocument') {
        my $textDocument = Perl::LanguageServer::Method::TextDocument->new($method, $request);
        $textDocument->dispatch;
    }

    return 1;
}

sub initialize {
    my ($self) = @_;

    my ($ok, $request) = $self->get_request;
    return $ok unless $ok;

    unless ($request->{content}{method} eq 'initialize') {
        # send error
        return 0;
    }
        
    my $response = Perl::LanguageServer::Response::InitializeResult->new;
    $response->send($request, $self->{writefh});

    ($ok, $request) = $self->get_request;
    return $ok unless $ok;

    unless ($request->{content}{method} eq 'initialized') {
        # send error
        return 0;
    }

    $self->{initialized} = 1;
    return 1;
}

sub run {
    my $server = Perl::LanguageServer->new;

    return unless $server->initialize;

    while (1) {
        my ($ok, $request) = $server->get_request;
        return unless $server->handle_request($request);
   }
}

1;