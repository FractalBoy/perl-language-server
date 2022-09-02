package PLS::Server::Request::Workspace::Configuration;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use List::Util;
use Scalar::Util;

use PLS::Parser::Document;
use PLS::Parser::Index;
use PLS::Parser::PackageSymbols;
use PLS::Parser::Pod;
use PLS::Server::Cache;
use PLS::Server::Request::TextDocument::PublishDiagnostics;
use PLS::Server::State;

=head1 NAME

PLS::Server::Request::Workspace::Configuration

=head1 DESCRIPTION

This is a message from the server to the client requesting that it send
the values of some configuration items.

PLS requests all configuration starting with C<pls.>.

This class also handles the response from the client which stores the configuration
in memory.

=cut

sub new
{
    my ($class) = @_;

    return bless {
        id     => undef,                       # assigned by the server
        method => 'workspace/configuration',
        params => {
                   items => [{section => 'perl'}, {section => 'pls'}]
                  }
                 }, $class;
} ## end sub new

sub handle_response
{
    my ($self, $response, $server) = @_;

    return if (Scalar::Util::reftype($response) ne 'HASH' or ref $response->{result} ne 'ARRAY');

    my $config = {};

    foreach my $result (@{$response->{result}})
    {
        next if (ref $result ne 'HASH');
        next if (exists $result->{pls} and not length $result->{pls});

        foreach my $key (keys %{$result})
        {
            $config->{$key} = $result->{$key} unless (length $config->{$key});
        }
    } ## end foreach my $result (@{$response...})

    convert_config($config);

    my $index = PLS::Parser::Index->new();
    my @inc;

    # Replace $ROOT_PATH with actual workspace paths in inc
    if (exists $config->{inc} and ref $config->{inc} eq 'ARRAY')
    {
        foreach my $inc (@{$config->{inc}})
        {
            foreach my $folder (@{$index->workspace_folders})
            {
                my $interpolated = $inc =~ s/\$ROOT_PATH/$folder/gr;
                push @inc, $interpolated;
            }
        } ## end foreach my $inc (@{$config->...})

        $config->{inc} = [List::Util::uniq sort @inc];
    } ## end if (exists $config->{inc...})

    if (exists $config->{syntax}{perl} and length $config->{syntax}{perl})
    {
        PLS::Parser::Pod->set_perl_exe($config->{syntax}{perl});
    }

    if (exists $config->{syntax}{args} and ref $config->{syntax}{args} eq 'ARRAY' and scalar @{$config->{syntax}{args}})
    {
        PLS::Parser::Pod->set_perl_args($config->{syntax}{args});
    }

    $PLS::Server::State::CONFIG = $config;

    # @INC may have changed - republish diagnostics
    foreach my $uri (@{PLS::Parser::Document->open_files()})
    {
        $server->send_server_request(PLS::Server::Request::TextDocument::PublishDiagnostics->new(uri => $uri));
    }

    PLS::Parser::PackageSymbols::start_package_symbols_process($config);
    PLS::Parser::PackageSymbols::start_imported_package_symbols_process($config);

    PLS::Server::Cache::warm_up();

    return;
} ## end sub handle_response

sub convert_config
{
    my ($config) = @_;

    if (length $config->{pls})
    {
        $config->{cmd} = $config->{pls} unless (length $config->{cmd});
        delete $config->{pls};
    }

    if (ref $config->{plsargs} eq 'ARRAY')
    {
        $config->{args} = $config->{plsargs} if (ref $config->{args} ne 'ARRAY');
        delete $config->{plsargs};
    }

    $config->{perltidy} = {} if (ref $config->{perltidy} ne 'HASH');

    if (length $config->{perltidyrc})
    {
        $config->{perltidy}{perltidyrc} = $config->{perltidyrc} unless (length $config->{perltidy}{perltidyrc});
        delete $config->{perltidyrc};
    }

    return;
} ## end sub convert_config

1;
