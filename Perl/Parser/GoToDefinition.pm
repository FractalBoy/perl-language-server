package Perl::Parser::GoToDefinition;

use File::Spec;
use PPI;
use PPI::Find;
use Scalar::Util qw(blessed);
use URI;

sub document_from_uri {
    my ($uri) = @_;

    my $file = URI->new($uri);
    my $document = PPI::Document->new($file->file);
    $document->index_locations;

    return $document;
}

sub go_to_definition {
    my ($document, $line, $column) = @_;

    # LSP defines position as 0-indexed, PPI defines it 1-indexed
    $line++; $column++;
    my $match = find_token_at_location($document, $line, $column);
    return undef unless $match;

    my $definition = find_variable_definition($document, $match);
    return undef unless $definition;
    # Subtract 1 again to get back to 0-indexed
    return ($definition->line_number - 1, $definition->visual_column_number - 1);
}

sub find_token_at_location {
    my ($document, $line, $column) = @_;

    my $find = PPI::Find->new(sub {
        my ($element) = @_;

        $element->line_number == $line &&
        $element->visual_column_number <= $column &&
        $element->visual_column_number + length($element->content) >= $column &&
        ($element->isa('PPI::Token::Symbol') || $element->isa('PPI::Token::Cast'));
    });

    return unless $find->start($document);
    my $match = $find->match; # let's just use the first match
    $find->finish;

    return undef unless $match;

    # find the thing we're casting, if this is a cast
    if ($match->isa('PPI::Token::Cast')) {
        while ($match = $match->next_sibling) {
            last if $match->isa('PPI::Token::Symbol');
        }
    }

    return $match;
}

sub find_variable_definition {
    my ($document, $element) = @_;
    return undef unless $element->isa('PPI::Token::Symbol');
    return $element if $element->parent->isa('PPI::Statement::Variable');

    my $parent = $element;
    while ($parent = $parent->parent) {
        next unless $parent->scope;

        for my $statement ($parent->children) {
            next unless $statement->isa('PPI::Statement::Variable');
            my @matches = grep { $_->symbol eq $element->symbol } $statement->symbols;
            next unless scalar @matches;
            return $matches[0];
        }
    }

    # if we get here, we didn't find any my, our, local, or state variables
    # let's find the first use of this variable name that affects this element 
    # we'll look in reverse, and keep the last one found
    my $match;
    $parent = $element;

    while ($parent = $parent->parent) {
        next unless $parent->scope;

        for my $statement (reverse $parent->children) {
            next unless $statement->isa('PPI::Statement');
            my @matches = grep {
                $_->isa('PPI::Token::Symbol') &&
                $_->symbol eq $element->symbol
            } $statement->children;
            next unless scalar @matches;
            $match = $matches[0];
        } 
    }

    return $match if $match;

    # if we get here, this is the first declaration.
    return $element;
}

=head2 is_scalar

Determines if a L<PPI::Element> is a scalar. This includes references.

=cut

sub is_scalar {
    my ($element) = @_;

    return 0 unless blessed $element;

    return $element->isa('PPI::Token::Symbol') &&
        # It starts with a $...
        $element->content =~ /^\$/ && 
        # ...and the next sibling is not a subscript.
        !$element->next_sibling->isa('PPI::Structure::Subscript');
}

=head2 is_hash

Determines if a L<PPI::Element> is a hash.

=cut

sub is_hash {
    my ($element) = @_;

    return 0 unless blessed $element;

    return $element->isa('PPI::Token::Symbol') &&
        (
            # It starts with a %...
            $element->content =~ /^%/ || 
            # ...or it starts with a $...
            $element->content =~ /^\$/ &&
            # ...and the next sibling is a subscript that uses {}.
            $element->next_sibling->isa('PPI::Structure::Subscript') &&
            $element->next_sibling->braces eq '{}'
        );
}

=head1 is_array

Determines if a L<PPI::Element> is an array

=cut

sub is_array {
    my ($element) = @_;

    return 0 unless blessed $element;

    return $element->isa('PPI::Token::Symbol') && (
        # It starts with a @...
        $element->content =~ /^@/ ||
        # ...or it starts with a $...
        $element->content =~ /^\$/ &&
        # ...and the next sibling is a subscript that uses [].
        $element->next_sibling->isa('PPI::Structure::Subscript') &&
        $element->next_sibling->braces eq '[]'
    );
}

1;