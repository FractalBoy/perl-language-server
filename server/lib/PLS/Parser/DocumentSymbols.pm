package PLS::Parser::DocumentSymbols;

use strict;
use warnings;

use experimental 'isa';

use PLS::Parser::Document;

use constant {
              PACKAGE  => 4,
              FUNCTION => 12,
              VARIABLE => 13,
              CONSTANT => 14
             };

sub new
{
    my ($class, $uri) = @_;

    my $document = PLS::Parser::Document->new(uri => $uri);
    return unless (ref $document eq 'PLS::Parser::Document');
    return bless {document => $document}, $class;
} ## end sub new

sub get_all_document_symbols
{
    my ($self) = @_;

    my @roots;
    $self->_get_all_document_symbols($self->document->{document}, \@roots);

    my @package_roots;

    my $packages = $self->document->get_packages();

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

    return scalar @package_roots ? \@package_roots : \@roots;
} ## end sub get_all_document_symbols

sub _get_all_document_symbols
{
    my ($self, $scope, $roots, $current) = @_;

    my $array = ref $current eq 'HASH' ? $current->{children} : $roots;

    if ($scope isa 'PPI::Document' or $scope isa 'PPI::Structure::Block')
    {
        foreach my $child ($scope->children)
        {
            $self->_get_all_document_symbols($child, $roots, $current);
        }
    } ## end if ($scope isa 'PPI::Document'...)
    elsif ($scope isa 'PPI::Statement::Sub' or $scope isa 'PPI::Statement::Scheduled')
    {
        my $range = PLS::Parser::Element->new(element => $scope)->range();

        $current = {
                    name           => $scope isa 'PPI::Statement::Sub' ? $scope->name : $scope->type,
                    kind           => FUNCTION,
                    range          => $range,
                    selectionRange => $range,
                    children       => []
                   };

        push @{$array}, $current;

        $self->_get_all_document_symbols($scope->block, $roots, $current);
    } ## end elsif ($scope isa 'PPI::Statement::Sub'...)
    elsif ($scope isa 'PPI::Statement::Variable')
    {
        push @{$array}, map {
            my $range = $_->range();

            {
             name           => $_->name,
             kind           => VARIABLE,
             range          => $range,
             selectionRange => $range
            }
        } map { @{$_->symbols} } @{$self->document->get_variable_statements($scope)};
    } ## end elsif ($scope isa 'PPI::Statement::Variable'...)
    elsif ($scope isa 'PPI::Statement::Include' and $scope->type eq 'use' and $scope->pragma eq 'constant')
    {
        push @{$array}, map {
            my $range = $_->range();

            {
             name           => $_->name,
             kind           => CONSTANT,
             range          => $range,
             selectionRange => $range
            }
        } @{$self->document->get_constants($scope)};
    } ## end elsif ($scope isa 'PPI::Statement::Include'...)
} ## end sub _get_all_document_symbols

sub document
{
    my ($self) = @_;

    return $self->{document};
}

1;
