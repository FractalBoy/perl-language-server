package PLS::Server::Response::Location;
use parent q(PLS::Server::Response);

use strict;

use PLS::Parser::GoToDefinition;
use JSON;

sub new {
    my ($class, $request) = @_;

    my $document = PLS::Parser::GoToDefinition::document_from_uri($request->{params}{textDocument}{uri});
    my $results = PLS::Parser::GoToDefinition::go_to_definition(
        $document,
        $request->{params}{position}{line},
        $request->{params}{position}{character}
    );

    my %self = (
        id => $request->{id},
        result => $results
    );

    return bless \%self, $class;
}

1;
