package PLS::Parser::DocumentSymbols;

use strict;
use warnings;

use feature 'state';

use IO::Async::Function;
use IO::Async::Loop;
use Scalar::Util qw(blessed);

use PLS::Parser::Document;

use constant {
              PACKAGE  => 4,
              FUNCTION => 12,
              VARIABLE => 13,
              CONSTANT => 14
             };

=head1 NAME

PLS::Parser::DocumentSymbols

=head1 DESCRIPTION

This class parses a document to find all symbols.
It returns a hierachy of the symbols, so that a tree structure can be displayed.

=cut

sub get_all_document_symbols_async
{
    my ($class, $uri) = @_;

    state $function;

    if (ref $function ne 'IO::Async::Function')
    {
        $function = IO::Async::Function->new(code => \&get_all_document_symbols);
        IO::Async::Loop->new->add($function);
    }

    my $text = PLS::Parser::Document->text_from_uri($uri);
    return $function->call(args => [$class, $uri, $text]);
} ## end sub get_all_document_symbols_async

sub get_all_document_symbols
{
    my ($class, $uri, $text) = @_;

    my $document = PLS::Parser::Document->new(uri => $uri, text => $text);
    return [] if (ref $document ne 'PLS::Parser::Document');

    my @roots;
    $class->_get_all_document_symbols($document, $document->{document}, \@roots);

    my @package_roots;

    my $packages = $document->get_packages();

    foreach my $index (0 .. $#{$packages})
    {
        my $line_start = $packages->[$index]->lsp_line_number;
        my $line_end   = $index == $#{$packages} ? undef : $packages->[$index + 1]->lsp_line_number;
        my $range      = $packages->[$index]->range();

        push @package_roots,
          {
            name           => $packages->[$index]->name,
            kind           => PACKAGE,
            range          => $range,
            selectionRange => $range,
            children       => [grep { $_->{range}{start}{line} > $line_start and (not defined $line_end or $_->{range}{end}{line} < $line_end) } @roots]
          };
    } ## end foreach my $index (0 .. $#{...})

    unless (scalar @package_roots)
    {
        my $range = PLS::Parser::Element->new(element => $document->{document})->range();

        push @package_roots,
          {
            name           => 'main',
            kind           => PACKAGE,
            range          => $range,
            selectionRange => $range,
            children       => \@roots
          };
    } ## end unless (scalar @package_roots...)

    return \@package_roots;
} ## end sub get_all_document_symbols

sub _get_all_document_symbols
{
    my ($class, $document, $scope, $roots, $current) = @_;

    my $array = ref $current eq 'HASH' ? $current->{children} : $roots;
    return unless blessed($scope);

    if ($scope->isa('PPI::Document') or $scope->isa('PPI::Structure::Block'))
    {
        foreach my $child ($scope->children)
        {
            $class->_get_all_document_symbols($document, $child, $roots, $current);
        }
    } ## end if ($scope->isa('PPI::Document'...))
    elsif ($scope->isa('PPI::Statement::Sub') or $scope->isa('PPI::Statement::Scheduled'))
    {
        # Don't show subroutine forward declarations
        return unless blessed($scope->block);
        return unless $scope->block->isa('PPI::Structure::Block');
        my $range = PLS::Parser::Element->new(element => $scope)->range();

        $current = {
                    name           => $scope->isa('PPI::Statement::Sub') ? $scope->name : $scope->type,
                    kind           => FUNCTION,
                    range          => $range,
                    selectionRange => $range,
                    children       => []
                   };

        push @{$array}, $current;

        $class->_get_all_document_symbols($document, $scope->block, $roots, $current);
    } ## end elsif ($scope->isa('PPI::Statement::Sub'...))
    elsif ($scope->isa('PPI::Statement::Variable'))
    {
        push @{$array}, map {
            my $range = $_->range();

            {
             name           => $_->name,
             kind           => VARIABLE,
             range          => $range,
             selectionRange => $range
            }
        } map { @{$_->symbols} } @{$document->get_variable_statements($scope)};
    } ## end elsif ($scope->isa('PPI::Statement::Variable'...))
    elsif ($scope->isa('PPI::Statement::Include') and $scope->type eq 'use' and $scope->pragma eq 'constant')
    {
        push @{$array}, map {
            my $range = $_->range();

            {
             name           => $_->name,
             kind           => CONSTANT,
             range          => $range,
             selectionRange => $range
            }
        } @{$document->get_constants($scope)};
    } ## end elsif ($scope->isa('PPI::Statement::Include'...))
} ## end sub _get_all_document_symbols

1;
