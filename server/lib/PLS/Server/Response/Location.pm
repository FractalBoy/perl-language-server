package PLS::Server::Response::Location;
use parent q(PLS::Server::Response);

use strict;
use warnings;

use PLS::Parser::GoToDefinition;

sub new {
    my ($class, $request) = @_;

    my $document = PLS::Parser::GoToDefinition::document_from_uri($request->{params}{textDocument}{uri});
    my $results = PLS::Parser::GoToDefinition::go_to_definition(
        $document,
        $request->{params}{position}{line},
        $request->{params}{position}{character}
    );

    if (ref $results eq 'ARRAY')
    {
        foreach my $result (@$results)
        {
            delete $result->{signature};
        }
    }

    my %self = (
        id => $request->{id},
        result => $results
    );

    return bless \%self, $class;
}

1;
