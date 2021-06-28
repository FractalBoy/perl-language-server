package PLS::Trie::Node;

use strict;
use warnings;

=head1 NAME

PLS::Trie::Node

=head1 DESCRIPTION

Node within a L<PLS::Trie>.

=cut

sub new
{
    my ($class) = @_;

    my %self = (
                children => {},
                value    => ''
               );

    return bless \%self, $class;
} ## end sub new

sub collect
{
    my ($self, $prefix) = @_;

    my @results;

    if (length $self->{value})
    {
        push @results, (join '', @$prefix);
    }

    foreach my $char (keys %{$self->{children}})
    {
        push @$prefix, $char;
        push @results, @{$self->{children}{$char}->collect($prefix)};
        pop @$prefix;
    } ## end foreach my $char (keys %{$self...})

    return \@results;
} ## end sub collect

1;
