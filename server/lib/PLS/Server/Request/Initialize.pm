package PLS::Server::Request::Initialize;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PPI::Document;
use URI;

use PLS::Parser::Document;
use PLS::Parser::Index;
use PLS::Server::Response::InitializeResult;
use PLS::Server::State;

=head1 NAME

PLS::Server::Request::Initialize

=head1 DESCRIPTION

This is the first request from the client to the server.

The client provides information about itself, and the server performs
some initialization for itself and returns its capabilities.

=cut

sub service
{
    my ($self) = @_;

    my $root_uri          = $self->{params}{rootUri};
    my $workspace_folders = $self->{params}{workspaceFolders};
    $workspace_folders = [] if (ref $workspace_folders ne 'ARRAY');
    @{$workspace_folders} = map { $_->{uri} } @{$workspace_folders};
    push @{$workspace_folders}, $root_uri if (not scalar @{$workspace_folders} and length $root_uri);
    @{$workspace_folders} = map { URI->new($_)->file } @{$workspace_folders};

    # Create and cache index object
    PLS::Parser::Index->new(workspace_folders => $workspace_folders);

    $PLS::Server::State::CLIENT_CAPABILITIES = $self->{params}{capabilities};

    return PLS::Server::Response::InitializeResult->new($self);
} ## end sub service

1;
