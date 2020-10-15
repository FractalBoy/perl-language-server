package PLS::Server::Request::Initialize;
use parent q(PLS::Server::Request::Base);

use strict;

use File::Find;
use File::Spec;
use JSON;
use PPI::Cache;
use PPI::Document;
use URI;

use PLS::Parser::GoToDefinition;
use PLS::Server::Response::InitializeResult;
use PLS::Server::State;

sub service {
    my ($self) = @_;

    my $root_uri = $self->{params}{rootUri};
    my $path = URI->new($root_uri);
    $PLS::Server::State::ROOT_PATH = $path->file;

    parse_and_cache();
    return PLS::Server::Response::InitializeResult->new($self);
}

sub parse_and_cache
{
    my $cache = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_ppi_cache');
    mkdir $cache unless (-d $cache);
    my $ppi_cache = PPI::Cache->new(path => $cache);
    PPI::Document->set_cache($ppi_cache);

    PLS::Parser::GoToDefinition::index_subroutine_declarations();
}

1;
