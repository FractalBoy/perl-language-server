package PLS::Server::Request::Initialize;
use parent q(PLS::Server::Request::Base);

use strict;

use File::Find;
use File::Spec;
use JSON;
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

    PLS::Parser::GoToDefinition::index_declarations();
    return PLS::Server::Response::InitializeResult->new($self);
}

1;
