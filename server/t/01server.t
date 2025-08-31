#!perl

use Test2::V0;

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
use URI;

use t::Communicate;

plan tests => 6;

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

    is(valid_response($response), T(),                                                                                  'valid response');
    is($response->{jsonrpc},      number(2.0),                                                                          'response is jsonrpc 2.0');
    is($response->{id},           number(0),                                                                            'response is id 0');
    is($response->{error},        hash { field code => -32_002; field message => 'server not yet initialized'; end() }, 'server not yet initialized');
}; ## end 'server not initialized' => sub

subtest 'initialize server' => sub {
    plan tests => 15;

    my $comm     = t::Communicate->new();
    my $response = initialize_server($comm);
    $comm->stop_server();

    is(valid_response($response), T(),       'valid response');
    is($response->{id},           number(0), 'response is id 0');

    is(scalar keys %{$response->{result}},               number(1),      'result has 1 key');
    is($response->{result}{capabilities},                hash { etc() }, 'response capabilities is json object');
    is(scalar keys %{$response->{result}{capabilities}}, number(12),     'capabilities has 12 keys');

    my $capabilities = $response->{result}{capabilities};

    is($capabilities->{definitionProvider},     T(), 'server is definition provider');
    is($capabilities->{documentSymbolProvider}, T(), 'server is document symbol provider');
    is($capabilities->{hoverProvider},          T(), 'server is hover provider');
    is(
        $capabilities->{signatureHelpProvider}, hash
        {
            field triggerCharacters => array { item '('; item ','; end() };
            end()
        },
        'server is signature help provider'
      );
    is($capabilities->{textDocumentSync},                hash { field openClose => JSON::PP::true; field change => 2; field save => JSON::PP::true; end() }, 'server does text document sync');
    is($capabilities->{documentFormattingProvider},      T(),                                                                                                'server is document formatting provider');
    is($capabilities->{documentRangeFormattingProvider}, T(),                                                                                                'server is document formatting provider');
    is(
        $capabilities->{completionProvider},
        hash
        {
            field triggerCharacters => array
            {
                item '>';
                item ':';
                item '$';
                item '@';
                item '%';
                item ' ';
                item '-';
                end()
            };
            field resolveProvider => JSON::PP::true;
            end()
        },
        'server is completion provider'
      );
    is(
        $capabilities->{executeCommandProvider}, hash
        {
            field commands => array { item 'pls.sortImports'; end() };
            end()
        },
        'server can execute commands'
      );
    is($capabilities->{workspaceSymbolProvider}, T(), 'server is workspace symbol provider');
}; ## end 'initialize server' => sub

subtest 'initial requests' => sub {
    plan tests => 8;
    my $comm = t::Communicate->new();
    initialize_server($comm);

    my @messages;

    foreach (1 .. 6)
    {
        push @messages, $comm->recv_message();
    }

    my $work_done_create    = List::Util::first { $_->{method} eq 'window/workDoneProgress/create' } @messages;
    my $work_done_begin     = List::Util::first { $_->{method} eq '$/progress' and $_->{params}{value}{kind} eq 'begin' } @messages;     ## no critic (RequireInterpolationOfMetachars)
    my $work_done_report    = List::Util::first { $_->{method} eq '$/progress' and $_->{params}{value}{kind} eq 'report' } @messages;    ## no critic (RequireInterpolationOfMetachars)
    my $work_done_end       = List::Util::first { $_->{method} eq '$/progress' and $_->{params}{value}{kind} eq 'end' } @messages;       ## no critic (RequireInterpolationOfMetachars)
    my $register_capability = List::Util::first { $_->{method} eq 'client/registerCapability' } @messages;
    my $configuration       = List::Util::first { $_->{method} eq 'workspace/configuration' } @messages;

    is(
        $work_done_create,
        hash
        {
            field method => 'window/workDoneProgress/create';
            field params => hash { field token => L() };
            etc()
        },
        'work done progress created'
      );

    my $token = $work_done_create->{params}{token};

    is(
        $configuration, hash
        {
            field method => 'workspace/configuration';
            field params => hash
            {
                field items => array
                {
                    item hash { field section => 'perl'; end() };
                    item hash { field section => 'pls';  end() };
                    end()
                };
                end();
            };
            etc()
        },
        'configuration request sent'
      );

    is(
        $register_capability, hash
        {
            field method => 'client/registerCapability';
            field params => hash
            {
                field registrations => array
                {
                    item hash
                    {
                        field method => 'workspace/didChangeConfiguration';
                        etc()
                    };
                    item hash
                    {
                        field method => 'workspace/didChangeWatchedFiles';
                        field registerOptions => hash {
                            field watchers => array
                            {
                                item hash { field globPattern => '**/*' }
                            }
                        };
                        etc()
                    } ## end hash
                };
                end();
            };
            etc()
        },
        'client register capability sent'
      );

    is(
        $work_done_begin, hash
        {
            field method => '$/progress';    ## no critic (RequireInterpolationOfMetachars)
            field params => hash
            {
                field token => $token;
                field value => hash
                {
                    field kind        => 'begin';
                    field title       => 'Indexing';
                    field percentage  => number(0);
                    field cancellable => F();
                } ## end hash
            };
            etc()
        },
        'work done begin sent'
      );

    is(
        $work_done_report, hash
        {
            field method => '$/progress';    ## no critic (RequireInterpolationOfMetachars)
            field params => hash
            {
                field token => $token;
                field value => hash
                {
                    field kind       => 'report';
                    field percentage => number(100);
                    field message => 'Indexed Communicate.pm (1/1)'
                }
            };
            etc();
        },
        'work done report sent'
      );

    is(
        $work_done_end, hash
        {
            field method => '$/progress';    ## no critic (RequireInterpolationOfMetachars)
            field params => hash
            {
                field token => $token;
                field value => hash
                {
                    field kind => 'end';
                    field message => 'Finished indexing all files'
                }
            };
            etc()
        },
        'work done report sent'
      );

    $comm->send_message(slurp('configuration.json', $configuration->{id}));
    my $uri         = open_file('Communicate.pm', $comm);
    my $diagnostics = $comm->recv_message();

    is(valid_notification($diagnostics), T(), 'diagnostics notification returned');
    is(
        $diagnostics, hash
        {
            field method => 'textDocument/publishDiagnostics';
            field params => hash
            {
                field uri => $uri;
                field diagnostics => array
                {
                    all_items hash
                    {
                        field code            => L();
                        field codeDescription => hash { field href => L() };
                        field message         => L();
                        field severity        => L();
                        field source          => 'perlcritic';
                        field range => hash
                        {
                            field start => hash
                            {
                                field line      => L();
                                field character => L();
                            };
                            field end => hash
                            {
                                field line      => L();
                                field character => L();
                            }
                        } ## end hash
                    };
                    etc();
                } ## end array
            };
            etc()
        },
        'diagnostics are valid',
        $diagnostics
      );

    $comm->stop_server();
}; ## end 'initial requests' => sub

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

    is(valid_response($response),   T(),                   'valid response');
    is($response->{id},             number($format->{id}), 'correct id');
    is($response->{error}{code},    number(-32_800),       'correct code');            # request cancelled = -32800
    is($response->{error}{message}, 'Request cancelled.',  'correct error message');
    $comm->stop_server();
}; ## end 'cancel request' => sub

subtest 'bad message' => sub {
    plan tests => 1;

    my $comm = t::Communicate->new();
    $comm->send_raw_message("Bad-Header: BAD\r\n\r\nnot json");
    chomp(my $error = $comm->recv_err());
    like($error, qr/no content-length header/i, 'no content length header error thrown');
    waitpid $comm->{pid}, 0;
}; ## end 'bad message' => sub

subtest 'shutdown and exit' => sub {
    plan tests => 5;

    my $comm = t::Communicate->new();
    initialize_server($comm);
    complete_initialization($comm);

    my $shutdown_response = $comm->send_message_and_recv_response(slurp('shutdown.json', 2));
    is($shutdown_response->{id}, number(2), 'got shutdown response');

    my $invalid_request = $comm->send_message_and_recv_response(slurp('formatting.json', 3));
    is($invalid_request->{id},          number( 3),      'got invalid request response');
    is($invalid_request->{error}{code}, number(-32_600), 'got correct error code');

    $comm->send_message(slurp('exit.json'));
    waitpid $comm->{pid}, 0;
    is($? >> 8, number(0), 'got 0 exit code when shutdown request sent before exit');

    $comm = t::Communicate->new();
    initialize_server($comm);
    complete_initialization($comm);

    $comm->send_message(slurp('exit.json'));
    waitpid $comm->{pid}, 0;
    is($? >> 8, number(1), 'got 1 exit code when exit request sent without shutdown');
}; ## end 'shutdown and exit' => sub
