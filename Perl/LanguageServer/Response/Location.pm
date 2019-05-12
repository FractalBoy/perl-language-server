package Perl::LanguageServer::Response::Location;
use parent q(Perl::LanguageServer::Response);

use strict;

use Perl::Parser::GoToDefinition;

sub new {
    my ($class, $request) = @_;

    my ($line, $column) = Perl::Parser::GoToDefinition::go_to_definition(
        $request->{params}{textDocument}{uri},
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