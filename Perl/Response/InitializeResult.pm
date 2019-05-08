package Perl::Response::InitializeResult;
use parent q(Perl::Response);

use strict;

sub new {
    my ($class) = @_;

    my %self = ( 
        result => {
            capabilities => {
                definitionProvider => 1,
                documentFormattingProvider => 1
            }
        }
    );

    return bless $self, $class;
}