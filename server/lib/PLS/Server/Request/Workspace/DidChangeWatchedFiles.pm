package PLS::Server::Request::Workspace::DidChangeWatchedFiles;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use List::Util qw(any uniq);
use Path::Tiny;

use PLS::Parser::Index;
use PLS::Server::Request::TextDocument::PublishDiagnostics;

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

    return if (ref $self->{params}{changes} ne 'ARRAY');

    my $index = PLS::Parser::Index->new();

    my @changed_files;

    foreach my $change (@{$self->{params}{changes}})
    {
        my $file = URI->new($change->{uri});
        next if (ref $file ne 'URI::file');

        if ($change->{type} == 3)
        {
            $index->cleanup_file($file->file);
            next;
        }

        next if ($file->file =~ /\/\.pls-tmp-[^\/]*$/);

        next unless $index->is_perl_file($file->file);
        next if $index->is_ignored($file->file);

        push @changed_files, $change->{uri};
    } ## end foreach my $change (@{$self...})

    @changed_files = uniq @changed_files;
    $index->index_files(@changed_files)->then(sub { Future->wait_all(@_) })->retain() if (scalar @changed_files);

    return;
} ## end sub service

1;
