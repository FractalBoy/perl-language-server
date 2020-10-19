package PLS::Parser::DocumentSymbols;

use strict;
use warnings;

use PPI;
use PPI::Find;

use PLS::Parser::Document;

use constant {
              PACKAGE  => 4,
              FUNCTION => 12,
              VARIABLE => 13,
              CONSTANT => 14
             };

sub get_all_document_symbols
{
    my ($uri) = @_;

    my $document = PLS::Parser::Document->new(uri => $uri);

    return [@{get_all_packages($document)}, @{get_all_subroutines($document)}, @{get_all_variables($document)}, @{get_all_constants($document)}];
} ## end sub get_all_document_symbols

sub get_all_packages
{
    my ($document) = @_;

    my $packages = $document->get_packages();
    my @results;

    foreach my $match (@$packages)
    {
        my $range = $match->range;

        push @results,
          {
            name           => $match->name,
            kind           => PACKAGE,
            range          => $range,
            selectionRange => $range
          };
    } ## end while (my $match = $find->...)

    return \@results;
} ## end sub get_all_packages

sub get_all_variables
{
    my ($document) = @_;

    my $statements = $document->get_variable_statements();
    my @results;

    foreach my $statement (@$statements)
    {
        foreach my $symbol (@{$statement->{symbols}})
        {
			my $range = $symbol->range;

            push @results,
              {
                name           => $symbol->name,
                kind           => VARIABLE,
                range          => $range,
                selectionRange => $range
              };
        } ## end foreach my $symbol ($match->...)
    } ## end while (my $match = $find->...)

    return \@results;
} ## end sub get_all_variables

sub get_all_subroutines
{
    my ($document) = @_;

    my $subroutines = $document->get_subroutines();
    my @results;

    foreach my $match (@$subroutines)
    {
        my $range = $match->range;

        push @results,
          {
            name           => $match->name,
            kind           => FUNCTION,
            range          => $range,
            selectionRange => $range
          };
    } ## end while (my $match = $find->...)

    return \@results;
} ## end sub get_all_subroutines

sub get_all_constants
{
    my ($document) = @_;

    my $constants = $document->get_constants();

    return [
        map {
            my $range = $_->range;

            {
             name           => $_->name,
             kind           => CONSTANT,
             range          => $range,
             selectionRange => $range
            }
          } @$constants
    ];
} ## end sub get_all_constants

1;
