package PLS::Server::Request::Workspace::Configuration;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Scalar::Util;

use PLS::Server::State;

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
    my ($self, $response) = @_;

    return unless (Scalar::Util::reftype $response eq 'HASH' and ref $response->{result} eq 'ARRAY');
    my $config = $response->{result}[0];
    return unless (ref $config eq 'HASH');
    
    # Replace $ROOT_PATH with actual workspace root in inc
    if (exists $config->{inc} and ref $config->{inc} eq 'ARRAY')
    {
        foreach my $inc (@{$config->{inc}})
        {
            $inc =~ s/\$ROOT_PATH/$PLS::Server::State::ROOT_PATH/g;
        }
    }

    $PLS::Server::State::CONFIG = $config;
    return;
} ## end sub handle_response

1;
