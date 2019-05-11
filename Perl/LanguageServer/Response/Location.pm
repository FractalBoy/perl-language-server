package Perl::LanguageServer::Response::Location;
use parent q(Perl::LanguageServer::Response);

use strict;

sub new {
    my ($class, $request) = @_;

    # right now, this always sends the cursor to the top left corner of the document
    my %self = (
        id => $request->{id},
        result => {
            uri => $request->{params}{textDocument}{uri},
            range => {
                start => {
                    line => 0,
                    character => 0,
                },
                end => {
                    line => 0,
                    character => 0
                }
            }
        }
    );

    return bless \%self, $class;
}

1;