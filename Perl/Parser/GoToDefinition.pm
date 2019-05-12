package Perl::Parser::GoToDefinition;

use File::Spec;
use PPI; 
use PPI::Find;
use URI;

sub go_to_definition {
    my ($uri, $line, $column) = @_;

    # LSP defines position as 0-indexed, PPI defines it 1-indexed
    $line++; $column++;
    my $uri = URI->new($uri);
    my $document = PPI::Document->new($uri->file);
    $document->index_locations;
    my $match = find_symbol_at_location($document, $line, $column);
    return ($line - 1, $column - 1) unless $match;

    my $name = $match->content;
    $name =~ s/^\$/%/ if is_hash($match);
    $name =~ s/^\$/@/ if is_array($match);

    my ($def_line, $def_column) = find_definition_location($document, $name);
    return ($def_line - 1, $def_column - 1);
}

sub find_symbol_at_location {
    my ($document, $line, $column) = @_;

    my $find = PPI::Find->new(sub {
        $_[0]->line_number == $line &&
        $_[0]->visual_column_number <= $column &&
        $_[0]->visual_column_number + length($_[0]->content) >= $column &&
        $_[0]->class eq 'PPI::Token::Symbol';
    });

    return unless $find->start($document);
    return $find->match; # let's just use the first match
}

sub find_definition_location {
    my ($document, $scalar) = @_;

    my $find_variable_statement = PPI::Find->new(sub {
        $_[0]->class eq 'PPI::Statement::Variable' &&
        grep { $_ eq $scalar } $_[0]->variables;
    });

    return unless $find_variable_statement->start($document);
    my $variable_statement = $find_variable_statement->match;
    return unless $variable_statement;

    $find = PPI::Find->new(sub {
        $_[0]->content eq $scalar &&
        $_[0]->class eq 'PPI::Token::Symbol';
    });

    return unless $find->start($variable_statement);
    my $declaration = $find->match;
    return ($declaration->line_number, $declaration->visual_column_number);
}

sub is_hash {
    # $hash{x}
    my ($element) = @_;

    return $element->next_sibling->class eq 'PPI::Structure::Subscript' &&
    $element->next_sibling->braces eq '{}';
}

sub is_hash_ref {
    # $$hash{x} or $hash->{x} or $hash->class_method
}

sub is_array {
    # $array[i]
    my ($element) = @_;

    return $element->next_sibling->class eq 'PPI::Structure::Subscript' &&
    $element->next_sibling->braces eq '[]';
}

sub is_array_ref {
    # $$array[i] or $array->[i] or $array->class_method
}

1;