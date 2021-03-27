package PLS::Parser::Pod::Builtin;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

sub new
{
    my ($class, @args) = @_;

    my %args = @args;
    my $self = $class->SUPER::new(%args);
    $self->{function} = $args{function};

    return $self;
} ## end sub new

sub name
{
    my ($self) = @_;

    return $self->{function};
} ## end sub name

sub find
{
    my ($self) = @_;

    my ($ok, $markdown) = $self->run_perldoc_command('-Tuf', $self->name);

    $self->{markdown} = $markdown if $ok;
    return $ok;
} ## end sub find

1;
