package PLS::Parser::Pod::ClassMethod;

use strict;
use warnings;

use parent 'PLS::Parser::Pod::Subroutine';

=head1 NAME

PLS::Parser::Pod::Builtin

=head1 DESCRIPTION

This is a subclass of L<PLS::Parser::Pod::Subroutine>, meant to distinguish regular subroutines from
class methods.

=cut

sub name
{
    my ($self) = @_;

    my $name = $self->{package} . '->' . $self->{subroutine};
}

1;
