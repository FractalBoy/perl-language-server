package PLS::Server::Request::Workspace::DidChangeWatchedFiles;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use List::Util qw(any uniq);
use Path::Tiny;

use PLS::Parser::Document;
use PLS::Server::Request::Diagnostics::PublishDiagnostics;

=head1 NAME

PLS::Server::Request::Workspace::DidChangeWatchedFiles

=head1 DESCRIPTION

This is a notification from the client to the server indicating
that one or more files that the server watched have changed.

The server queues up these files to be re-indexed.

=cut

sub service
{
    my ($self, $server) = @_;

    return unless (ref $self->{params}{changes} eq 'ARRAY');

    my $index = PLS::Parser::Document->get_index();

    my @changed_files;
    my $any_deletes;

    foreach my $change (@{$self->{params}{changes}})
    {
        my $file = URI->new($change->{uri});

        next unless (ref $file eq 'URI::file');

        if ($change->{type} == 3)
        {
            $any_deletes = 1;
            next;
        }

        next unless $index->is_perl_file($file->file);
        next if $index->is_ignored($file->file);

        push @changed_files, $file->file;
    } ## end foreach my $change (@{$self...})

    $index->cleanup_old_files() if $any_deletes;

    @changed_files = uniq @changed_files;
    $index->index_files(@changed_files) if (scalar @changed_files);

    return;
} ## end sub service

1;
