package PLS::Server::Request::Workspace::DidChangeWorkspaceFolders;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Future;
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

    my @futures;

    foreach my $folder (@{$added})
    {
        my $path = URI->new($folder->{uri})->file;
        push @futures, $index->index_workspace($path);
    }

    Future->wait_all(@futures)->get();

    return;
} ## end sub service

1;
