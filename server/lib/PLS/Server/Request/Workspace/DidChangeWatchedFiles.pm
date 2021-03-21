package PLS::Server::Request::Workspace::DidChangeWatchedFiles;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use Coro;
use List::Util qw(any uniq);

use PLS::Parser::Document;

sub service
{
    my ($self) = @_;

    return unless (ref $self->{params}{changes} eq 'ARRAY');

    my $index       = PLS::Parser::Document->get_index();
    my $any_deletes = any { $_->{type} == 3 } @{$self->{params}{changes}};

    if ($any_deletes)
    {
        async
        {
            my $lock       = $index->lock();
            my $index_hash = $index->index();
            $index->cleanup_old_files($index_hash);
            $index->save($index_hash);
        } ## end async
    } ## end if ($any_deletes)

    my @changed_files;

    foreach my $change (@{$self->{params}{changes}})
    {
        my $file = URI->new($change->{uri});

        next unless (ref $file eq 'URI::file');
        next if $change->{type} == 3;
        next unless $index->is_perl_file($file->file);

        push @changed_files, $file->file;
    } ## end foreach my $change (@{$self...})

    @changed_files = uniq @changed_files;
    $index->index_files(@changed_files) if (scalar @changed_files);
    return;
} ## end sub service

1;
