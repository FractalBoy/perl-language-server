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

    my $root_uri = $self->{params}{rootUri};
    my $path     = URI->new($root_uri);
    $PLS::Server::State::ROOT_PATH = $path->file;

    my $index = PLS::Parser::Index->new(root => $path->file);
    $index->index_files();
    $index->load_trie();
    PLS::Parser::Document->set_index($index);
    return PLS::Server::Response::InitializeResult->new($self);
} ## end sub service

1;
