package PLS::Server::Request::Initialize;
use parent q(PLS::Server::Request::Base);

use strict;

use Coro;
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
    my $cache = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_cache');
    mkdir $cache unless (-d $cache);
    my $ppi_cache = PPI::Cache->new(path => $cache);
    PPI::Document->set_cache($ppi_cache);

    my $perl_files = PLS::Parser::GoToDefinition::get_all_perl_files();

    async {
        foreach my $perl_file (@_)
        {
            my $document = PPI::Document->new($perl_file);
            cede;
        }
    } @$perl_files;
}

1;
