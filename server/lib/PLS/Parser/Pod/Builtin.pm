package PLS::Parser::Pod::Builtin;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

=head1 NAME

PLS::Parser::Pod::Builtin

=head1 DESCRIPTION

This attempts to find POD for a Perl builtin functions or keywords.

=cut

sub new
{
    my ($class, @args) = @_;

    my %args = @args;
    my $self = $class->SUPER::new(%args);
    $self->{function} = $args{function};

    return $self;
} ## end sub new

sub find
{
    my ($self) = @_;

    my ($ok, $markdown) = $self->run_perldoc_command('-Tuf', $self->{function});

    $self->{markdown} = $markdown if $ok;
    return $ok;
} ## end sub find

1;
