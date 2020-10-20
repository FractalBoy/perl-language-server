package PLS::Parser::Pod::ClassMethod;

use strict;
use warnings;

use parent 'PLS::Parser::Pod::Subroutine';

sub name
{
    my ($self) = @_;

    my $name = $self->{package} . '->' . $self->{subroutine};
}

1;
