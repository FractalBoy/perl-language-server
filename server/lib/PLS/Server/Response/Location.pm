package PLS::Server::Response::Location;
use parent q(PLS::Server::Response);

use strict;

use PLS::Parser::GoToDefinition;

sub new {
    my ($class, $request) = @_;

    my $document = PLS::Parser::GoToDefinition::document_from_uri($request->{params}{textDocument}{uri});
    my ($line, $column) = PLS::Parser::GoToDefinition::go_to_definition(
        $document,
        $request->{params}{position}{line},
        $request->{params}{position}{character}
    );

    # right now, this always sends the cursor to the top left corner of the document
    my %self = (
        id => $request->{id},
        result => {
            uri => $request->{params}{textDocument}{uri},
            range => {
                start => {
                    line => $line,
                    character => $column,
                },
                end => {
                    line => $line,
                    character => $column
                }
            }
        }
    );

    return bless \%self, $class;
}

1;
