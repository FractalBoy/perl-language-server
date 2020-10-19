package PLS::Server::Response::SignatureHelp;
use parent q(PLS::Server::Response);

use strict;
use warnings;

use PLS::Parser::GoToDefinition;

sub new {
    my ($class, $request) = @_;

    my $document =
      PLS::Parser::GoToDefinition::document_from_uri($request->{params}{textDocument}{uri});

    my $results = PLS::Parser::GoToDefinition::go_to_definition(
        $document,
        $request->{params}{position}{line},
        $request->{params}{position}{character} - 1 # we want the word before the open paren
    );

    my @signatures = map { $_->{signature} } @$results;

    my %self = (
        id => $request->{id},
        result => scalar @signatures ? { signatures => \@signatures } : undef
    );

    return bless \%self, $class;
}

1;
