package PLS::Server::Request::Workspace::Configuration;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Scalar::Util;

use PLS::Parser::Document;
use PLS::Parser::Pod;
use PLS::Server::State;
use PLS::Server::Request::Diagnostics::PublishDiagnostics;

=head1 NAME

PLS::Server::Request::Workspace::Configuration

=head1 DESCRIPTION

This is a message from the server to the client requesting that it send
the values of some configuration items.

PLS requests all configuration starting with C<perl.>.

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
                   items => [{section => 'perl'}]
                  }
                 }, $class;
} ## end sub new

sub handle_response
{
    my ($self, $response, $server) = @_;

    return unless (Scalar::Util::reftype $response eq 'HASH' and ref $response->{result} eq 'ARRAY');
    my $config = $response->{result}[0];
    return unless (ref $config eq 'HASH');

    # Replace $ROOT_PATH with actual workspace root in inc
    if (exists $config->{inc} and ref $config->{inc} eq 'ARRAY' and length $PLS::Server::State::ROOT_PATH)
    {
        foreach my $inc (@{$config->{inc}})
        {
            $inc =~ s/\$ROOT_PATH/$PLS::Server::State::ROOT_PATH/g;
        }
    } ## end if (exists $config->{inc...})

    if (exists $config->{cwd} and length $config->{cwd} and length $PLS::Server::State::ROOT_PATH)
    {
        $config->{cwd} =~ s/\$ROOT_PATH/$PLS::Server::State::ROOT_PATH/g;
        chdir $config->{cwd};
    }

    if (exists $config->{syntax}{perl} and length $config->{syntax}{perl})
    {
        PLS::Parser::Pod->set_perl_exe($config->{syntax}{perl});
    }

    $PLS::Server::State::CONFIG = $config;

    # @INC may have changed - republish diagnostics
    foreach my $uri (@{PLS::Parser::Document->open_files()})
    {
        $server->send_server_request(PLS::Server::Request::Diagnostics::PublishDiagnostics->new(uri => $uri, unsaved => 1));
    }

    return;
} ## end sub handle_response

1;
