#!perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::RealBin/..";
}

use File::Copy;
use File::Spec;
use File::Temp;
use JSON::PP;
use List::Util qw(first all);
use Test::More tests => 6;
use URI;

use t::Communicate;

# Copy code to non-hidden directory.
my $code_dir = File::Temp->newdir();
File::Copy::copy(File::Spec->catfile($FindBin::RealBin, 'Communicate.pm'), $code_dir);

sub slurp
{
    my ($file, $id) = @_;

    my $path = File::Spec->catfile($FindBin::RealBin, 'packets', $file);
    open my $fh, '<', $path;
    my $json = do { local $/; <$fh> };
    my $obj  = JSON::PP->new->utf8->decode($json);
    $obj->{id} = $id // 0 if (exists $obj->{id});
    if (length $obj->{method} and $obj->{method} eq 'initialize')
    {
        $obj->{params}{rootUri}          = URI::file->new($code_dir)->as_string;
        $obj->{params}{workspaceFolders} = [{uri => $obj->{params}{rootUri}}];
    }
    return $obj;
} ## end sub slurp

sub open_file
{
    my ($file, $comm) = @_;

    my $path = File::Spec->catfile($code_dir, $file);
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

    my $config_req = $comm->recv_message();
    my $config     = slurp('configuration.json', $config_req->{id});

    $comm->send_message($config);

    foreach (1 .. 5)
    {
        $comm->recv_message();
    }

    return;
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
    cmp_ok(scalar keys %{$response->{result}{capabilities}}, '==', 12, 'capabilities has 12 keys');

    my $capabilities = $response->{result}{capabilities};

    ok($capabilities->{definitionProvider},     'server is definition provider');
    ok($capabilities->{documentSymbolProvider}, 'server is document symbol provider');
    ok($capabilities->{hoverProvider},          'server is hover provider');
    is_deeply($capabilities->{signatureHelpProvider}, {triggerCharacters => ['(', ',']},                                          'server is signature help provider');
    is_deeply($capabilities->{textDocumentSync},      {openClose         => JSON::PP::true, change => 2, save => JSON::PP::true}, 'server does text document sync');
    ok($capabilities->{documentFormattingProvider},      'server is document formatting provider');
    ok($capabilities->{documentRangeFormattingProvider}, 'server is document formatting provider');
    is_deeply($capabilities->{completionProvider},     {triggerCharacters => ['>', ':', '$', '@', '%', ' ', '-'], resolveProvider => JSON::PP::true}, 'server is completion provider');
    is_deeply($capabilities->{executeCommandProvider}, {commands          => ['pls.sortImports']},                                                    'server can execute commands');
    ok($capabilities->{workspaceSymbolProvider}, 'server is workspace symbol provider');
};

subtest 'initial requests' => sub {
    plan tests => 30;
    my $comm = t::Communicate->new();
    initialize_server($comm);

    my @messages;

    foreach (1 .. 6)
    {
        push @messages, $comm->recv_message();
    }

    my $work_done_create    = List::Util::first { $_->{method} eq 'window/workDoneProgress/create' } @messages;
    my $work_done_begin     = List::Util::first { $_->{method} eq '$/progress' and $_->{params}{value}{kind} eq 'begin' } @messages;
    my $work_done_report    = List::Util::first { $_->{method} eq '$/progress' and $_->{params}{value}{kind} eq 'report' } @messages;
    my $work_done_end       = List::Util::first { $_->{method} eq '$/progress' and $_->{params}{value}{kind} eq 'end' } @messages;
    my $register_capability = List::Util::first { $_->{method} eq 'client/registerCapability' } @messages;
    my $configuration       = List::Util::first { $_->{method} eq 'workspace/configuration' } @messages;

    my $token = $work_done_create->{params}{token};

    is($work_done_create->{method}, 'window/workDoneProgress/create', 'work done progress created');
    ok(length($token), 'token provided');

    is($configuration->{method}, 'workspace/configuration', 'configuration request sent');
    is_deeply($configuration->{params}, {items => [{section => 'perl'}, {section => 'pls'}]}, 'correct configuration section');

    is($register_capability->{method}, 'client/registerCapability', 'client register capability sent');
    cmp_ok(@{$register_capability->{params}{registrations}}, '==', 2, 'two registrations sent');
    is($register_capability->{params}{registrations}[0]{method}, 'workspace/didChangeConfiguration', 'did change configuration capability sent');
    is($register_capability->{params}{registrations}[1]{method}, 'workspace/didChangeWatchedFiles',  'did change watched files capability sent');
    cmp_ok(@{$register_capability->{params}{registrations}[1]{registerOptions}{watchers}}, '==', 1, 'correct number of watchers');
    is($register_capability->{params}{registrations}[1]{registerOptions}{watchers}[0]{globPattern}, '**/*', 'correct glob pattern');

    is($work_done_begin->{method},               '$/progress', 'work done begin sent');
    is($work_done_begin->{params}{token},        $token,       'correct token');
    is($work_done_begin->{params}{value}{kind},  'begin',      'begin sent first');
    is($work_done_begin->{params}{value}{title}, 'Indexing',   'correct title');
    cmp_ok($work_done_begin->{params}{value}{percentage}, '==', 0, 'correct percentage');
    ok(!$work_done_begin->{params}{value}{cancellable}, 'work is not cancellable');

    is($work_done_report->{method},                 '$/progress',                   'work done report sent');
    is($work_done_report->{params}{token},          $token,                         'correct token');
    is($work_done_report->{params}{value}{kind},    'report',                       'report sent second');
    is($work_done_report->{params}{value}{message}, 'Indexed Communicate.pm (1/1)', 'correct message');
    cmp_ok($work_done_report->{params}{value}{percentage}, '==', 100, 'correct percentage');

    is($work_done_end->{method},                 '$/progress',                  'work done report sent');
    is($work_done_end->{params}{token},          $token,                        'correct token');
    is($work_done_end->{params}{value}{kind},    'end',                         'end sent last');
    is($work_done_end->{params}{value}{message}, 'Finished indexing all files', 'correct message');

    $comm->send_message(slurp('configuration.json', $configuration->{id}));
    my $uri         = open_file('Communicate.pm', $comm);
    my $diagnostics = $comm->recv_message();

    ok(valid_notification($diagnostics), 'diagnostics notification returned');
    is($diagnostics->{method},                  'textDocument/publishDiagnostics', 'got diagnostics after configuration sent');
    is($diagnostics->{params}{uri},             $uri,                              'got diagnostics for correct file');
    is(ref $diagnostics->{params}{diagnostics}, 'ARRAY',                           'diagnostics is an array');
    ok(
        (
         List::Util::all
         {
                   length $_->{code}
               and length $_->{codeDescription}{href}
               and length $_->{message}
               and length $_->{severity}
               and $_->{source} eq 'perlcritic'
               and length $_->{range}{start}{line}
               and length $_->{range}{start}{character}
               and length $_->{range}{end}{line}
               and length $_->{range}{end}{character}
         } ## end List::Util::all
         @{$diagnostics->{params}{diagnostics}}
        ),
        'diagnostics are valid'
      );

    $comm->stop_server();
};

subtest 'cancel request' => sub {
    plan tests => 4;

    my $comm = t::Communicate->new();
    initialize_server($comm);
    complete_initialization($comm);
    my $uri    = open_file('Communicate.pm', $comm);
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
    like($error, qr/no content-length header/i, 'no content length header error thrown');
    waitpid $comm->{pid}, 0;
};

subtest 'shutdown and exit' => sub {
    plan tests => 5;

    my $comm = t::Communicate->new();
    initialize_server($comm);
    complete_initialization($comm);

    my $shutdown_response = $comm->send_message_and_recv_response(slurp('shutdown.json', 2));
    cmp_ok($shutdown_response->{id}, '==', 2, 'got shutdown response');

    my $invalid_request = $comm->send_message_and_recv_response(slurp('formatting.json', 3));
    cmp_ok($invalid_request->{id},          '==', 3,      'got invalid request response');
    cmp_ok($invalid_request->{error}{code}, '==', -32600, 'got correct error code');

    $comm->send_message(slurp('exit.json'));
    waitpid $comm->{pid}, 0;
    cmp_ok($? >> 8, '==', 0, 'got 0 exit code when shutdown request sent before exit');

    $comm = t::Communicate->new();
    initialize_server($comm);
    complete_initialization($comm);

    $comm->send_message(slurp('exit.json'));
    waitpid $comm->{pid}, 0;
    cmp_ok($? >> 8, '==', 1, 'got 1 exit code when exit request sent without shutdown');
};
