package PLS::Parser::Element;

use strict;
use warnings;

use List::Util qw(any first);
use Scalar::Util qw(blessed);

=head1 NAME

PLS::Parser::Element

=head1 DESCRIPTION

This is an abstraction of a L<PPI::Element> with additional functionality.

=head1 METHODS

=cut

sub new
{
    my ($class, @args) = @_;

    my %args = @args;

    my %self = (ppi_element => $args{element}, file => $args{file}, document => $args{document});
    return if (not blessed($args{element}) or not $args{element}->isa('PPI::Element'));
    return bless \%self, $class;
} ## end sub new

=head2 ppi_line_number

This is the line number of the element according to PPI.

=cut

sub ppi_line_number
{
    my ($self) = @_;

    return $self->element->line_number;
}

=head2 ppi_column_number

This is the column number of the element according to PPI.

=cut

sub ppi_column_number
{
    my ($self) = @_;

    return $self->element->column_number;
}

=head2 lsp_line_number

This is the line number of the element according to the Language Server Protocol.

=cut

sub lsp_line_number
{
    my ($self) = @_;

    my $line_number = $self->ppi_line_number;
    return 0 unless $line_number;
    return $line_number - 1;
} ## end sub lsp_line_number

=head2 lsp_column_number

This is the column number of the element according to the Language Server Protocol.

=cut

sub lsp_column_number
{
    my ($self) = @_;

    my $column_number = $self->ppi_column_number;
    return 0 unless $column_number;
    return $column_number - 1;
} ## end sub lsp_column_number

=head2 location_info

This is information about the location of the element, to be stored in the index.

=cut

sub location_info
{
    my ($self) = @_;

    return {
            file     => $self->{file},
            location => {
                         line_number   => $self->lsp_line_number,
                         column_number => $self->lsp_column_number
                        }
           };
} ## end sub location_info

=head2 content

This is the content of the element.
This is the same as L<PPI::Element::content>.

=cut

sub content
{
    my ($self) = @_;

    return $self->element->content;
}

=head2 name

This is the name of the element.
This is the same as the result of C<content>, in the base class.

=cut

sub name
{
    my ($self) = @_;

    return $self->content;
}

=head2 package_name

This finds a package name at the given column number inside this element.

=cut

sub package_name
{
    my ($self, $column_number) = @_;

    my $element = $self->element;
    $column_number++;

    if (    blessed($element->statement)
        and $element->statement->isa('PPI::Statement::Include')
        and $element->statement->type eq 'use')
    {
        # This is a 'use parent/base' statement. The import is a package, not a subroutine.
        if ($element->statement->module eq 'parent' or $element->statement->module eq 'base')
        {
            my $import = _extract_import($element, $column_number);
            return $import if (length $import);
        }

        # This is likely a 'use' statement with an explicit subroutine import.
        my $package = $element->statement->module;
        my $import  = _extract_import($element, $column_number);
        return $element->statement->module, $import if (length $import);
    } ## end if (blessed($element->...))

    # Regular use statement, no explicit imports
    if (blessed($element->statement) and $element->statement->isa('PPI::Statement::Include') and $element->statement->type eq 'use')
    {
        return $element->statement->module;
    }

    # Class method call, cursor is over the package name
    if (    $element->isa('PPI::Token::Word')
        and ref $element->snext_sibling eq 'PPI::Token::Operator'
        and $element->snext_sibling eq '->')
    {
        return $element->content;
    } ## end if ($element->isa('PPI::Token::Word'...))

    # Declaring parent class using @ISA directly.
    if (    blessed($element->statement)
        and $element->statement->isa('PPI::Statement::Variable')
        and $element->statement->type eq 'our'
        and any { $_->symbol eq '@ISA' } $element->statement->symbols)
    {
        my $import = _extract_import($element, $column_number);
        return $import if (length $import);
    } ## end if (blessed($element->...))

    return;
} ## end sub package_name

=head2 method_name

This finds a method name in the current element.

=cut

sub method_name
{
    my ($self) = @_;

    my $element = $self->element;

    return
      if (   not blessed($element)
          or not $element->isa('PPI::Token::Word')
          or not blessed($element->sprevious_sibling)
          or not $element->sprevious_sibling->isa('PPI::Token::Operator')
          or $element->sprevious_sibling ne '->');

    return $element->content =~ s/^SUPER:://r;
} ## end sub method_name

=head2 class_method_package_and_name

This finds a class method within the current element and returns the class and method name.

=cut

sub class_method_package_and_name
{
    my ($self) = @_;

    my $element = $self->element;

    return
      if (   not blessed($element)
          or not $element->isa('PPI::Token::Word')
          or not blessed($element->sprevious_sibling)
          or not $element->sprevious_sibling->isa('PPI::Token::Operator')
          or not $element->sprevious_sibling eq '->'
          or not blessed($element->sprevious_sibling->sprevious_sibling)
          or not $element->sprevious_sibling->sprevious_sibling->isa('PPI::Token::Word'));

    return ($element->sprevious_sibling->sprevious_sibling->content, $element->content);
} ## end sub class_method_package_and_name

=head2 subroutine_package_and_name

This finds a fully qualified function call within this element and returns the package
and function name.

=cut

sub subroutine_package_and_name
{
    my ($self) = @_;

    my $element = $self->element;

    return unless blessed($element);

    my $content = '';

    return if (    blessed($element->sprevious_sibling)
               and $element->sprevious_sibling->isa('PPI::Token::Operator')
               and $element->sprevious_sibling eq '->');

    if ($element->isa('PPI::Token::Symbol') and $element->content =~ /^&/)
    {
        $content = $element->content =~ s/^&//r;
    }
    elsif ($element->isa('PPI::Token::Word'))
    {
        $content = $element->content;
    }
    else
    {
        return;
    }

    if ($content =~ /::/)
    {
        my @parts      = split /::/, $content;
        my $subroutine = pop @parts;
        my $package    = join '::', @parts;
        return $package, $subroutine;
    } ## end if ($content =~ /::/)
    else
    {
        return '', $content;
    }

    return;
} ## end sub subroutine_package_and_name

=head2 variable_name

This finds a variable in the current element and returns its name.

=cut

sub variable_name
{
    my ($self) = @_;

    my $element = $self->element;
    return if (not blessed($element) or not $element->isa('PPI::Token::Symbol'));

    return $element->symbol;
} ## end sub variable_name

=head2 cursor_on_package

This determines if the cursor at the given column number is on a package name.

=cut

sub cursor_on_package
{
    my ($self, $column_number) = @_;

    my $element = $self->element;

    my $index         = $column_number - $element->column_number;
    my @parts         = split /::/, $element->content;
    my $current_index = 1;

    for (my $i = 0 ; $i <= $#parts ; $i++)
    {
        my $part = $parts[$i];

        if ($index <= $current_index + length $part)
        {
            return 0 if ($i == $#parts);
            pop @parts;
            return 1;
        } ## end if ($index <= $current_index...)

        $current_index += length $part;
    } ## end for (my $i = 0 ; $i <= ...)

    return;
} ## end sub cursor_on_package

=head2 _extract_import

This extracts an import within a C<use> statement, which may be a package or function name.

=cut

sub _extract_import
{
    my ($element, $column_number) = @_;

    # Single import, single quotes or 'q' string.
    if ($element->isa('PPI::Token::Quote::Single') or $element->isa('PPI::Token::Quote::Literal'))
    {
        return $element->literal;
    }

    # Single import, double quotes or 'qq' string.
    if ($element->isa('PPI::Token::Quote::Double') or $element->isa('PPI::Token::Quote::Interpolate'))
    {
        return $element->string;
    }

    # Multiple imports, 'qw' list.
    if ($element->isa('PPI::Token::QuoteLike::Words'))
    {
        my $import = _get_string_from_qw($element, $column_number);
        return $import if (length $import);
    }

    # Multiple imports, using a list.
    if ($element->isa('PPI::Structure::List'))
    {
        my $import = _get_string_from_list($element, $column_number);
        return $import if (length $import);
    }

    return;
} ## end sub _extract_import

=head2 _get_string_from_list

This finds the string in a list at a given column number.

=cut

sub _get_string_from_list
{
    my ($element, $column_number) = @_;

    foreach my $expr ($element->children)
    {
        next unless $expr->isa('PPI::Statement::Expression');

        foreach my $item ($expr->children)
        {
            # Only handle quoted strings. Could be another or list, but that's too complicated.
            next unless $item->isa('PPI::Token::Quote');

            if ($item->column_number <= $column_number and ($item->column_number + length $item->content) >= $column_number)
            {
                return $item->literal if ($item->can('literal'));
                return $item->string;
            }
        } ## end foreach my $item ($expr->children...)
    } ## end foreach my $expr ($element->...)
} ## end sub _get_string_from_list

=head2 _get_string_from_qw

This gets a string from a C<qw> quoted list at a given column number.

=cut

sub _get_string_from_qw
{
    my ($element, $column_number) = @_;

    my ($content) = $element->content =~ /qw[[:graph:]](.+)[[:graph:]]/;
    return unless (length $content);
    my @words          = split /(\s+)/, $content;
    my $current_column = $element->column_number + 3;

    # Figure out which word the mouse is hovering on.
    foreach my $word (@words)
    {
        my $next_start = $current_column + length $word;

        if ($word !~ /^\s*$/ and $current_column <= $column_number and $next_start > $column_number)
        {
            return $word;
        }

        $current_column = $next_start;
    } ## end foreach my $word (@words)
} ## end sub _get_string_from_qw

=head2 range

This provides the range where this element is located, in a format the
Language Server Protocol can understand.

=cut

sub range
{
    my ($self) = @_;

    my $lines            = () = $self->element->content =~ m{($/)}g;
    my ($last_line)      = $self->element->content =~ m{(.+)$/$};
    my $last_line_length = defined $last_line ? length $last_line : length $self->element->content;

    return {
            start => {
                      line      => $self->lsp_line_number,
                      character => $self->lsp_column_number
                     },
            end => {
                    line      => $self->lsp_line_number + $lines,
                    character => $lines == 0 ? $self->lsp_column_number + $last_line_length : $last_line_length
                   }
           };
} ## end sub range

=head2 length

This returns the length of this element.

=cut

sub length
{
    my ($self) = @_;

    return length $self->name;
}

=head2 parent

This returns the parent element of this element, as a L<PLS::Parser::Element> object.

=cut

sub parent
{
    my ($self) = @_;

    return $self->{_parent} if (ref $self->{_parent} eq 'PLS::Parser::Element');
    return unless $self->element->parent;
    return PLS::Parser::Element->new(file => $self->{file}, element => $self->element->parent);
} ## end sub parent

=head2 previous_sibling

This returns the previous significant sibling of this element, as a L<PLS::Parser::Element> object.

=cut

sub previous_sibling
{
    my ($self) = @_;

    return $self->{_previous_sibling} if (ref $self->{_previous_sibling} eq 'PLS::Parser::Element');
    return unless $self->element->sprevious_sibling;
    $self->{_previous_sibling} = PLS::Parser::Element->new(file => $self->{file}, element => $self->element->sprevious_sibling);
    return $self->{_previous_sibling};
} ## end sub previous_sibling

=head2 previous_sibling

This returns the next significant sibling of this element, as a L<PLS::Parser::Element> object.

=cut

sub next_sibling
{
    my ($self) = @_;

    return $self->{_next_sibling} if (ref $self->{_next_sibling} eq 'PLS::Parser::Element');
    return unless $self->element->snext_sibling;
    $self->{_next_sibling} = PLS::Parser::Element->new(file => $self->{file}, element => $self->element->snext_sibling);
    return $self->{_next_sibling};
} ## end sub next_sibling

=head2 children

This returns all of this element's children, as L<PLS::Parser::Element> objects.

=cut

sub children
{
    my ($self) = @_;

    return @{$self->{_children}} if (ref $self->{_children} eq 'ARRAY');
    return unless $self->element->can('children');
    $self->{_children} = [map { PLS::Parser::Element->new(file => $self->{file}, element => $_) } $self->element->children];
    return @{$self->{_children}};
} ## end sub children

=head2 tokens

This returns all the tokens in the current element, as L<PLS::Parser::Element> objects.
Tokens correspond to all of the L<PPI::Token> objects in the current element.

=cut

sub tokens
{
    my ($self) = @_;

    return @{$self->{_tokens}} if (ref $self->{_tokens} eq 'ARRAY');
    return unless $self->element->can('tokens');
    $self->{_tokens} = [map { PLS::Parser::Element->new(file => $self->{file}, element => $_) } $self->element->tokens];
    return @{$self->{_tokens}};
} ## end sub tokens

=head2 element

Returns the L<PPI::Element> object for this element.

=cut

sub element
{
    my ($self) = @_;

    return $self->{ppi_element};
}

=head2 type

Returns the type of L<PPI::Element> that this element is associated with.

=cut

sub type
{
    my ($self) = @_;

    return ref $self->element;
}

1;
