package PLS::Server::Request::Workspace::DidChangeWatchedFiles;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use PLS::Parser::Document;

sub service
{
    my ($self) = @_;

    return unless (ref $self->{params}{changes} eq 'ARRAY');

    my $index = PLS::Parser::Document->get_index();

    foreach my $change (@{$self->{params}{changes}})
    {
        my $file = URI->new($change->{uri});
        next unless (ref $file eq 'URI::file');
        next unless $index->is_perl_file($file->file);
        if ($change->{type} == 1 or $change->{type} == 2)
        {
            $index->index_files($file->file);
        }
        elsif ($change->{type} == 3)
        {
            $index->cleanup_old_files();
        }
    } ## end foreach my $change (@{$self...})
} ## end sub service

1;
