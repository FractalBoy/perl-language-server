package PLS::Parser::Pod::Package;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

=head1 NAME

PLS::Parser::Pod::Package

=head1 DESCRIPTION

This is a subclass of L<PLS::Parser::Pod>, used to find POD for a package.

=cut

sub new
{
    my ($class, @args) = @_;

    my %args = @args;
    my $self = $class->SUPER::new(%args);
    $self->{package} = $args{package};

    return $self;
} ## end sub new

sub find
{
    my ($self) = @_;

    my $definitions;
    $definitions = $self->{index}->find_package($self->{package}) if (ref $self->{index} eq 'PLS::Parser::Index');

    if (ref $definitions eq 'ARRAY' and scalar @$definitions)
    {
        foreach my $definition (@$definitions)
        {
            my $path = URI->new($definition->{uri})->file;
            open my $fh, '<', $path or next;
            my $text = do { local $/; <$fh> };
            my ($ok, $markdown) = $self->get_markdown_from_text(\$text);

            if ($ok)
            {
                $self->{markdown} = $markdown;
                return 1;
            }
        } ## end foreach my $definition (@$definitions...)
    } ## end if (ref $definitions eq...)

    my ($ok, $markdown) = $self->get_markdown_for_package($self->{package});
    $self->{markdown} = $markdown if $ok;

    return $ok;
} ## end sub find

1;
