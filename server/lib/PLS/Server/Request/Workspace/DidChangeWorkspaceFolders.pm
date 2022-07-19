package PLS::Server::Request::Workspace::DidChangeWorkspaceFolders;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use URI;

use PLS::Parser::Index;

=head1 NAME

PLS::Server::Request::Workspace::DidChangeWorkspaceFolders

=head1 DESCRIPTION

This is a notification from the client to the server that
workspace folders were added or removed.

=cut

sub service
{
    my ($self) = @_;

    my $added   = $self->{params}{event}{added};
    my $removed = $self->{params}{event}{removed};

    my $index = PLS::Parser::Index->new();

    foreach my $folder (@{$removed})
    {
        my $path = URI->new($folder->{uri})->file;
        $index->deindex_workspace($path);
    }

    foreach my $folder (@{$added})
    {
        my $path = URI->new($folder->{uri})->file;
        $index->index_workspace($path);
    }

    return;
} ## end sub service

1;
