#!perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::RealBin/..";
}

use File::Path;
use File::Spec;
use JSON::PP;
use List::Util qw(first all);
use Test::More tests => 5;
use URI;

use t::Communicate;

sub slurp
{
    my ($file, $id) = @_;

    my $path = File::Spec->catfile($FindBin::RealBin, 'packets', $file);
    open my $fh, '<', $path;
    my $json = do { local $/; <$fh> };
    my $obj  = JSON::PP->new->utf8->decode($json);
    $obj->{id}              = $id // 0                                       if (exists $obj->{id});
    $obj->{params}{rootUri} = URI::file->new("$FindBin::RealBin")->as_string if (length $obj->{method} and $obj->{method} eq 'initialize');
    return $obj;
} ## end sub slurp

sub open_file
{
    my ($file, $comm) = @_;

    my $path = File::Spec->catfile($FindBin::RealBin, $file);
    open my $fh, '<', $path;
    my $text       = do { local $/; <$fh> };
    my $uri        = URI::file->new($path)->as_string;
    my $open_files = slurp('didopen.json', 1);
    $open_files->{params}{textDocument}{uri}  = $uri;
    $open_files->{params}{textDocument}{text} = $text;

    $comm->send_message(JSON::PP->new->utf8->encode($open_files));

    return $uri;
} ## end sub open_file

sub valid_packet
{
    my ($packet) = @_;

    return 0 if (ref $packet ne 'HASH');
    return 0 if ($packet->{jsonrpc} ne '2.0');
    return 1;
} ## end sub valid_packet

sub valid_request
{
    my ($packet) = @_;

    return 0 unless valid_packet($packet);
    return 0 unless (length $packet->{id});
    return 0 unless (length $packet->{method});
    return 0 if (exists $packet->{params} and ref $packet->{params} ne 'HASH' and ref $packet->{params} ne 'ARRAY');
    return 1;
} ## end sub valid_request

sub valid_response
{
    my ($packet) = @_;

    return 0 unless valid_packet($packet);
    return 0 unless (length $packet->{id});
    return 0 if (not exists $packet->{result} and not exists $packet->{error});
    return 1;
} ## end sub valid_response

sub valid_notification
{
    my ($packet) = @_;

    return 0 unless valid_packet($packet);
    return 0 unless (length $packet->{method});
    return 0 if (exists $packet->{params} and ref $packet->{params} ne 'HASH' and ref $packet->{params} ne 'ARRAY');
    return 1;
} ## end sub valid_notification
use Data::Dumper;

sub initialize_server
{
    my ($comm) = @_;

    my $request  = slurp 'initialize.json';
    my $response = $comm->send_message_and_recv_response($request);
    $request = slurp 'initialized.json';
    $comm->send_message($request);
    return $response;
} ## end sub initialize_server

sub complete_initialization
{
    my ($comm) = @_;

    my @messages;
    push @messages, $comm->recv_message();
    push @messages, $comm->recv_message();

    my $config_req = first { $_->{method} eq 'workspace/configuration' } @messages;

    my $config = slurp('configuration.json', $config_req->{id});
    $comm->send_message($config);
} ## end sub complete_initialization

subtest 'server not initialized' => sub {
    plan tests => 4;

    my $comm     = t::Communicate->new();
    my $request  = slurp 'initialized.json';
    my $response = $comm->send_message_and_recv_response($request);
    $comm->stop_server();

    ok(valid_response($response), 'valid response');
    cmp_ok($response->{jsonrpc}, '==', 2.0, 'response is jsonrpc 2.0');
    cmp_ok($response->{id},      '==', 0,   'response is id 0');
    is_deeply($response->{error}, {code => -32002, message => 'server not yet initialized'}, 'server not yet initialized');
};

subtest 'initialize server' => sub {
    plan tests => 15;

    my $comm     = t::Communicate->new();
    my $response = initialize_server($comm);
    $comm->stop_server();

    ok(valid_response($response), 'valid response');
    cmp_ok($response->{id}, '==', 0, 'response is id 0');

    cmp_ok(scalar keys %{$response->{result}}, '==', 1, 'result has 1 key');
    is(ref $response->{result}{capabilities}, 'HASH', 'response capabilities is json object');
    cmp_ok(scalar keys %{$response->{result}{capabilities}}, '==', 9, 'capabiltiies has 9 keys');

    my $capabilities = $response->{result}{capabilities};

    ok($capabilities->{definitionProvider},     'server is definition provider');
    ok($capabilities->{documentSymbolProvider}, 'server is document symbol provider');
    ok($capabilities->{hoverProvider},          'server is hover provider');
    is_deeply($capabilities->{signatureHelpProvider}, {triggerCharacters => ['(', ',']},                                          'server is signature help provider');
    is_deeply($capabilities->{textDocumentSync},      {openClose         => JSON::PP::true, change => 2, save => JSON::PP::true}, 'server does text document sync');
    ok($capabilities->{documentFormattingProvider},      'server is document formatting provider');
    ok($capabilities->{documentRangeFormattingProvider}, 'server is document formatting provider');
    is_deeply($capabilities->{completionProvider},     {triggerCharacters => ['>', ':', '$', '@', '%'], resolveProvider => JSON::PP::true}, 'server is completion provider');
    is_deeply($capabilities->{executeCommandProvider}, {commands          => ['perl.sortImports']},                                         'server can execute commands');

    chomp(my $error = $comm->recv_err());
  SKIP:
    {
        skip('timing issue - indexing not logged yet', 1) unless (length $error);
        like($error, qr/Indexing/, 'indexing logged');
    }
};

subtest 'initial requests' => sub {
    plan tests => 6;
    my $comm = t::Communicate->new();
    initialize_server($comm);
    my @messages;

    push @messages, $comm->recv_message();
    push @messages, $comm->recv_message();

    ok((all { valid_request($_) } @messages), 'two json objects returned');
    my $config_req       = first { $_->{method} eq 'workspace/configuration' } @messages;
    my $capabilities_req = first { $_->{method} eq 'client/registerCapability' } @messages;
    ok(valid_request($config_req),       'got configuration request');
    ok(valid_request($capabilities_req), 'got register capability request');

    # put .pm file in "open files" list
    my $uri = open_file('Communicate.pm', $comm);

    my $config = slurp('configuration.json', $config_req->{id});

    # sending configuration should result in diagnostics request being sent back for .pm
    # file above, if all goes well.
    my $diagnostics = $comm->send_message_and_recv_response($config);
    ok(valid_notification($diagnostics), 'diagnostics notification returned');
    is($diagnostics->{method},      'textDocument/publishDiagnostics', 'got diagnostics after configuration sent');
    is($diagnostics->{params}{uri}, $uri,                              'got diagnostics for correct file');

    $comm->stop_server();
};

subtest 'cancel request' => sub {
    plan tests => 4;

    my $comm = t::Communicate->new();
    initialize_server($comm);
    complete_initialization($comm);
    my $uri = open_file('Communicate.pm', $comm);
    $comm->recv_message();    # publish diagnostics - throw this away
    my $format = slurp('formatting.json', 2);

    my $cancel = slurp('cancel.json');
    $format->{params}{textDocument}{uri} = $uri;

    $cancel->{params}{id} = $format->{id};

    # request formatting and then cancel immediately.
    # should receive a response that the request was canceled.
    $comm->send_message($format);
    $comm->send_message($cancel);
    my $response = $comm->recv_message();

    ok(valid_response($response), 'valid response');
    cmp_ok($response->{id},          '==', $format->{id}, 'correct id');
    cmp_ok($response->{error}{code}, '==', -32800,        'correct code');    # request cancelled = -32800
    is($response->{error}{message}, 'Request cancelled.', 'correct error message');
    $comm->stop_server();
};

subtest 'bad message' => sub {
    plan tests => 1;

    my $comm = t::Communicate->new();
    $comm->send_raw_message("Bad-Header: BAD\r\n\r\nnot json");
    chomp(my $error = $comm->recv_err());
    $comm->stop_server();
    like($error, qr/no content-length header/i, 'no content length header error thrown');
};

END
{
    # Clean up index created by server
    eval { File::Path::rmtree("$FindBin::RealBin/.pls_cache") };
}
