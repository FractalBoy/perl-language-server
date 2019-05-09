package Perl::LanguageServer::Response::InitializeResult;
use parent q(Perl::LanguageServer::Response);

use strict;

sub new {
    my ($class, $id) = @_;

    my %self = ( 
        result => {
            capabilities => {
                definitionProvider => \1,
#                documentFormattingProvider => \1
            }
        }
    );

    return bless \%self, $class;
}

1;