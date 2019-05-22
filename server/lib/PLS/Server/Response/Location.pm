package PLS::Server::Response::Location;
use parent q(PLS::Server::Response);

use strict;

use PLS::Parser::GoToDefinition;
use JSON;

sub new {
    my ($class, $request) = @_;

    my $document = PLS::Parser::GoToDefinition::document_from_uri($request->{params}{textDocument}{uri});
    my @result = PLS::Parser::GoToDefinition::go_to_definition(
        $document,
        $request->{params}{position}{line},
        $request->{params}{position}{character}
    );

    my $result;

    $result = {
        uri => $request->{params}{textDocument}{uri},
        range => {
            start => {
                line => $result[0],
                character => $result[1],
            },
            end => {
                line => $result[0],
                character => $result[1]
            }
        }
    } if @result;

    my %self = (
        id => $request->{id},
        result => $result
    );

    return bless \%self, $class;
}

1;
