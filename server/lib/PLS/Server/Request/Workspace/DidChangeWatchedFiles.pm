package PLS::Server::Request::Workspace::DidChangeWatchedFiles;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Coro;
use List::Util qw(any uniq);
use Path::Tiny;

use PLS::Parser::Document;
use PLS::Server::Request::Diagnostics::PublishDiagnostics;

sub service
{
    my ($self, $server) = @_;

    return unless (ref $self->{params}{changes} eq 'ARRAY');

    my $index = PLS::Parser::Document->get_index();

    my @changed_files;
    my @changed_uris;
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
        push @changed_uris, $change->{uri};

    } ## end foreach my $change (@{$self...})

    @changed_uris = uniq @changed_uris;

    async {
        foreach my $uri (@changed_uris)
        {
            $server->{server_requests}->put(PLS::Server::Request::Diagnostics::PublishDiagnostics->new(uri => $uri)) if PLS::Parser::Document->is_open($uri);
        }
    }; 

    $index->cleanup_old_files() if $any_deletes;

    @changed_files = uniq @changed_files;
    $index->index_files(@changed_files) if (scalar @changed_files);

    return;
} ## end sub service

1;
