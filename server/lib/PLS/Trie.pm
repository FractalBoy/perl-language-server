package PLS::Trie;

use strict;
use warnings;

use PLS::Trie::Node;

=head1 NAME

PLS::Trie

=head1 DESCRIPTION

A trie for fast searching of a word by prefix.

=head1 SYNOPSIS

    my $trie = PLS::Trie->new();
    $trie->insert('me', 'me');
    $trie->insert('met', 'met');
    $trie->insert('method', 'method');
    $trie->find('me') # ['me', 'met', 'method']
    $trie->find('met') # ['met', 'method']
    $trie->find('meth') # ['method']

=cut

sub new
{
    my ($class) = @_;

    my %self = (root => PLS::Trie::Node->new());

    return bless \%self, $class;
} ## end sub new

sub find
{
    my ($self, $prefix) = @_;

    my @prefix = split //, $prefix;
    my $node   = $self->_get_node(\@prefix);
    return unless (ref $node eq 'PLS::Trie::Node');
    return $node->collect(\@prefix);
} ## end sub find

sub _get_node
{
    my ($self, $key) = @_;

    my $node = $self->{root};

    foreach my $char (@$key)
    {
        if (ref $node->{children}{$char} eq 'PLS::Trie::Node')
        {
            $node = $node->{children}{$char};
        }
        else
        {
            return;
        }
    } ## end foreach my $char (@$key)

    return $node;
} ## end sub _get_node

sub find_node
{
    my ($self, $key) = @_;

    my @chars = split //, $key;
    return $self->_get_node(\@chars);
} ## end sub find_node

sub insert
{
    my ($self, $key, $value) = @_;

    my $node = $self->{root};

    foreach my $char (split //, $key)
    {
        if (ref $node->{children}{$char} ne 'PLS::Trie::Node')
        {
            $node->{children}{$char} = PLS::Trie::Node->new();
        }

        $node = $node->{children}{$char};
    } ## end foreach my $char (split //,...)

    $node->{value} = $value;
} ## end sub insert

sub delete
{
    my ($self, $key) = @_;

    my @chars     = split //, $key;
    my $last_char = pop @chars;
    my $node      = $self->_get_node(\@chars);
    return unless (ref $node eq 'PLS::Trie::Node');
    delete $node->{children}{$last_char};
} ## end sub delete

1;
