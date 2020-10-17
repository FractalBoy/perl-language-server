package PLS::Parser::DocumentSymbols;

use strict;
use warnings;

use PPI;
use PPI::Find;

use PLS::Parser::GoToDefinition;

use constant {
    PACKAGE => 4,
    FUNCTION => 12,
    VARIABLE => 13,
    CONSTANT => 14
};

sub get_all_document_symbols
{
    my ($uri) = @_;

    my $document = PLS::Parser::GoToDefinition::document_from_uri($uri);

    return [
        @{get_all_packages($document)},
        @{get_all_subroutines($document)},
        @{get_all_variables($document)},
        @{get_all_constants($document)}
    ];
}

sub get_all_packages
{
    my ($document) = @_;

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Package') });
    return [] unless $find->start($document);

    my @results;
    
    while (my $match = $find->match)
    {
        my $range = _get_range($match);

        push @results, {
            name => $match->namespace,
            kind => PACKAGE,
            range => $range,
            selectionRange => $range
        };
    }

    return \@results;
}

sub get_all_variables
{
    my ($document) = @_;

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Variable') });
    return [] unless $find->start($document);

    my @results;

    while (my $match = $find->match)
    {
        my $range = _get_range($match);

        foreach my $symbol ($match->symbols)
        {
            my $selection_range = _get_range($symbol);

            push @results, {
                name => $symbol->symbol,
                kind => VARIABLE,
                range => $range,
                selectionRange => $selection_range
            };
        }
    }

    return \@results;
}

sub get_all_subroutines
{
    my ($document) = @_;

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Sub') and not $_[0]->isa('PPI::Statement::Scheduled') });
    return [] unless $find->start($document);

    my @results;

    while (my $match = $find->match)
    {
        my $range = _get_range($match);

        push @results, {
            name => $match->name,
            kind => FUNCTION,
            range => $range,
            selectionRange => $range
        };
    }

    return \@results;
}

sub get_all_constants
{
    my ($document) = @_;

    my $constants = PLS::Parser::GoToDefinition::get_constants($document);

    return [
        map {
            my $range = _get_range($_);

            {
                name => $_->content,
                kind => CONSTANT,
                range => $range,
                selectionRange => $range
            }
        }
        @$constants
    ];
}

sub _get_range
{
    my ($element) = @_;

    my %range = (
        start => {
            line => $element->line_number - 1,
            character => $element->column_number - 1
        },
        end => {
            line => $element->line_number - 1,
            character => ($element->column_number + length($element->content) - 1)
        }
    );

    return \%range;
}

1;
