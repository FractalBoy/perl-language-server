package PLS::Server::Response::WorkspaceSymbols;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use PLS::Parser::Index;

sub new
{
    my ($class, $request) = @_;

    my $query = $request->{params}{query};

    my $index = PLS::Parser::Index->new();
    my @symbols;

    foreach my $name (keys %{$index->subs})
    {
        next if ($name !~ /\Q$query\E/i);

        my $refs = $index->subs->{$name};

        foreach my $sub (@{$refs})
        {
            push @symbols,
              {
                name     => $name,
                kind     => 12,
                location => $sub
              };
        } ## end foreach my $sub (@{$refs})
    } ## end foreach my $name (keys %{$index...})

    foreach my $name (keys %{$index->packages})
    {
        next if ($name !~ /\Q$query\E/i);

        my $refs = $index->packages->{$name};

        foreach my $package (@{$refs})
        {
            push @symbols,
              {
                name     => $name,
                kind     => 4,
                location => $package
              };
        } ## end foreach my $package (@{$refs...})
    } ## end foreach my $name (keys %{$index...})

    return
      bless {
             id     => $request->{id},
             result => \@symbols
            }, $class;
} ## end sub new

1;
