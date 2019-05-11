package Perl::LanguageServer;

use strict;

use AnyEvent;
use Coro;
use Coro::AnyEvent;
use Coro::Handle;
use Data::Dumper;
use JSON;

use Perl::LanguageServer::Request;
use Perl::LanguageServer::Response;

sub new {
    my ($class, $readfh, $writefh) = @_;

    my $readfh = $readfh || \*STDIN;
    my $writefh = $writefh || \*STDOUT;

    my %self = (
        readfh => Coro::Handle->new_from_fh($readfh),
        writefh => Coro::Handle->new_from_fh($writefh)
    );

    return bless \%self, $class;
}

sub recv {
    my ($self) = @_;

    my %headers;
    my $readfh = $self->{readfh};
    my $line; 

    while ($readfh->readable && $readfh->sysread(my $buffer, 1)) {
        $line .= $buffer;
        last if $line eq "\r\n";
        next unless $line =~ /\r\n$/;
        $line =~ s/^\s+|\s+$//g;
        my ($field, $value) = split /: /, $line;
        $headers{$field} = $value;
        $line = '';
    }

    my $size = $headers{'Content-Length'};
    die 'no Content-Length header provided' unless $size;

    my $length = $readfh->sysread(my $raw, $size) if $readfh->readable;
    die 'content length does not match header' unless $length == $size;

    my $content = decode_json $raw;

    return Perl::LanguageServer::Request->new($content);
}

sub send {
    my ($self, $response) = @_;

    my $json = $response->serialize;
    my $size = length($json);

    $self->{writefh}->syswrite("Content-Length: $size\r\n\r\n") if $self->{writefh}->writable;
    $self->{writefh}->syswrite($json) if $self->{writefh}->writable;
}

sub run {
    my $requests = Coro::Channel->new;
    my $responses = Coro::Channel->new;
    my $server = Perl::LanguageServer->new;

    my $stderr = Coro::Handle->new_from_fh(\*STDERR);

    async_pool {
        # check for requests and service them
        while (my $request = $requests->get) {
            my $response = $request->service($server);
            next unless defined $response;
            $responses->put($response);
        }
    };

    async_pool {
        # check for responses and send them
        while (my $response = $responses->get) {
            $server->send($response);
        }
    };

    # main loop
    while (1) {
        # check for requests and drop them on the channel to be serviced by existing threads
        my $request = $server->recv;
        $requests->put($request);
    }
}

1;