package PLS::Parser::Pod::Variable;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

use Pod::Simple::Search;

=head1 NAME

PLS::Parser::Pod::Variable

=head1 DESCRIPTION

This is a subclass of L<PLS::Parser::Pod> for finding POD for a Perl builtin variable.

=cut

sub new
{
    my ($class, @args) = @_;

    my %args = @args;
    my $self = $class->SUPER::new(%args);
    $self->{variable} = $args{variable};
    $self->{package}  = $args{package};

    return $self;
} ## end sub new

sub find
{
    my ($self) = @_;

    my ($ok, $markdown) = $self->run_perldoc_command('-Tuv', $self->{variable});

    if ($ok)
    {
        $self->{markdown} = $markdown;
        return 1;
    }

    return 0 unless (length $self->{package});

    my $search  = Pod::Simple::Search->new();
    my $include = $self->get_clean_inc();
    $search->inc(0);
    my $path = $search->find($self->{package}, @{$include});
    ($ok, $markdown) = $self->find_pod_in_file($path, $self->{variable});

    if ($ok)
    {
        $self->{markdown} = $markdown;
        return 1;
    }

    return 0;
} ## end sub find

1;
