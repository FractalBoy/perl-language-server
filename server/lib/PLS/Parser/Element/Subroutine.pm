package PLS::Parser::Element::Subroutine;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

use List::Util qw(any);

sub location_info
{
    my ($self) = @_;

    my $info = $self->SUPER::location_info;

    my $signature = $self->signature;
    $info->{signature} = $signature if (ref $signature eq 'HASH');

    return $info;
} ## end sub location_info

sub signature
{
    my ($self) = @_;

    my $block = $self->{ppi_element}->block;
    return unless (ref $block eq 'PPI::Structure::Block');

    # only looking at first variable statement, for performance sake.
    foreach my $child ($block->children)
    {
        next   unless $child->isa('PPI::Statement::Variable');
        return unless $child->type eq 'my';
        return
          unless any { $_->isa('PPI::Token::Magic') and $_->content eq '@_' }
        $child->children;
        return unless (scalar $child->variables);
        return {label => $child->content, parameters => [map { {label => $_} } $child->variables]};
    } ## end foreach my $child ($block->...)

    return;
} ## end sub signature

sub name
{
    my ($self) = @_;

    return $self->{ppi_element}->name;
}

1;
