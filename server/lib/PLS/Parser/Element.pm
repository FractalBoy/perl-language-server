package PLS::Parser::Element;

use strict;
use warnings;

use Scalar::Util;

sub new
{
    my ($class, @args) = @_;

    my %args = @args;

    my %self = (ppi_element => $args{element}, file => $args{file});
    return unless (Scalar::Util::blessed($args{element}) and $args{element}->isa('PPI::Element'));
    return bless \%self, $class;
} ## end sub new

sub ppi_line_number
{
    my ($self) = @_;

    return $self->{ppi_element}->line_number;
}

sub ppi_column_number
{
    my ($self) = @_;

    return $self->{ppi_element}->column_number;
}

sub lsp_line_number
{
    my ($self) = @_;

    return $self->ppi_line_number - 1;
}

sub lsp_column_number
{
    my ($self) = @_;

    return $self->ppi_column_number - 1;
}

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

sub content
{
    my ($self) = @_;

    return $self->{ppi_element}->content;
}

sub name
{
    my ($self) = @_;

    return $self->content;
}

sub package_name
{
    my ($self, $column_number) = @_;

    my $element = $self->{ppi_element};
    $column_number++;

    if (Scalar::Util::blessed($element->parent) and $element->parent->isa('PPI::Statement::Include') and $element->parent->type eq 'use')
    {
        # This is a 'use parent' statement. The import is a package, not a subroutine.
        if ($element->parent->module eq 'parent' and ($element->isa('PPI::Token::Quote') or $element->isa('PPI::Token::QuoteLike')))
        {
            if ($element->can('literal'))
            {
                my ($module) = $element->literal;
                return $module, undef;
            }
            else
            {
                return $element->string, undef;
            }
        } ## end if ($element->parent->...)

        # This is likely a 'use' statement with an explicit subroutine import.
        my $package = $element->parent->module;

        # Single import, single quotes or 'q' string.
        if ($element->isa('PPI::Token::Quote::Single') or $element->isa('PPI::Token::Quote::Literal'))
        {
            return $package, $element->literal;
        }
        # Single import, double quotes or 'qq' string.
        if ($element->isa('PPI::Token::Quote::Double') or $element->isa('PPI::Token::Quote::Interpolate'))
        {
            return $package, $element->string;
        }
        # Multiple imports, 'qw' list.
        if ($element->isa('PPI::Token::QuoteLike::Words'))
        {
            my ($content)      = $element->content =~ /^qw.(.+).$/;
            my @words          = split /(\s+)/, $content;
            my $current_column = $element->column_number + 3;

            # Figure out which word the mouse is hovering on.
            foreach my $word (@words)
            {
                my $next_start = $current_column + length $word;

                if ($word !~ /^\s*$/ and $current_column <= $column_number and $next_start > $column_number)
                {
                    return $package, $word;
                }

                $current_column = $next_start;
            } ## end foreach my $word (@words)
        } ## end if ($element->isa('PPI::Token::QuoteLike::Words'...))
        # Multiple imports, using a list.
        if ($element->isa('PPI::Structure::List'))
        {
            foreach my $expr ($element->children)
            {
                next unless $expr->isa('PPI::Statement::Expression');

                foreach my $item ($expr->children)
                {
                    # Only handle quoted strings. Could be another or list, but that's too complicated.
                    next unless $item->isa('PPI::Token::Quote');

                    if ($item->column_number <= $column_number and ($item->column_number + length $item->content) >= $column_number)
                    {
                        return $package, $item->literal if ($item->can('literal'));
                        return $package, $item->string;
                    } ## end if ($item->column_number...)
                } ## end foreach my $item ($expr->children...)
            } ## end foreach my $expr ($element->...)
        } ## end if ($element->isa('PPI::Structure::List'...))
    } ## end if (Scalar::Util::blessed...)

    # Regular use statement, no explicit imports
    if ($element->isa('PPI::Statement::Include') and $element->type eq 'use')
    {
        return $element->module;
    }
    if (    $element->isa('PPI::Token::Word')
        and ref $element->snext_sibling eq 'PPI::Token::Operator'
        and $element->snext_sibling eq '->')
    {
        return $element->content;
    } ## end if ($element->isa('PPI::Token::Word'...))

    return;
} ## end sub package_name

sub method_name
{
    my ($self) = @_;

    my $element = $self->{ppi_element};
    return unless $element->isa('PPI::Token::Word');
    return unless (ref $element->sprevious_sibling eq 'PPI::Token::Operator' and $element->sprevious_sibling eq '->');
    return $element->content;
} ## end sub method_name

sub class_method_package_and_name
{
    my ($self) = @_;

    my $element = $self->{ppi_element};
    return unless $element->isa('PPI::Token::Word');
    return unless (ref $element->sprevious_sibling eq 'PPI::Token::Operator' and $element->sprevious_sibling eq '->');
    return unless (ref $element->sprevious_sibling->sprevious_sibling eq 'PPI::Token::Word');

    return ($element->sprevious_sibling->sprevious_sibling->content, $element->content);
} ## end sub class_method_package_and_name

sub subroutine_package_and_name
{
    my ($self) = @_;

    my $element = $self->{ppi_element};
    return unless Perl::Critic::Utils::is_function_call($element);
    return unless $element->isa('PPI::Token::Word');

    if ($element->content =~ /::/)
    {
        my @parts      = split /::/, $element->content;
        my $subroutine = pop @parts;
        my $package    = join '::', @parts;
        return $package, $subroutine;
    } ## end if ($element->content ...)
    else
    {
        return '', $element->content;
    }

    return;
} ## end sub subroutine_package_and_name

sub variable_name
{
    my ($self) = @_;

    my $element = $self->{ppi_element};
    return unless $element->isa('PPI::Token::Symbol');
    return $element->symbol;
} ## end sub variable_name

sub cursor_on_package
{
    my ($self, $column_number) = @_;

    my $element = $self->{ppi_element};

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

sub range
{
    my ($self) = @_;

    return {
            start => {
                      line      => $self->lsp_line_number,
                      character => $self->lsp_column_number
                     },
            end => {
                    line      => $self->lsp_line_number,
                    character => ($self->lsp_column_number + length $self->name)
                   }
           };
} ## end sub range

sub parent
{
    my ($self) = @_;

    my $parent = PLS::Parser::Element->new(file => $self->{file}, element => $self->{ppi_element}->parent);
    return $parent;
} ## end sub parent

sub previous_sibling
{
    my ($self) = @_;

    return PLS::Parser::Element->new(file => $self->{file}, element => $self->{ppi_element}->sprevious_sibling);
}

sub next_sibling
{
    my ($self) = @_;

    return PLS::Parser::Element->new(file => $self->{file}, element => $self->{ppi_element}->snext_sibling);
}

sub children
{
    my ($self) = @_;

    return unless $self->{ppi_element}->can('children');
    return map { PLS::Parser::Element->new(file => $self->{file}, element => $_) } $self->{ppi_element}->children;
} ## end sub children

sub tokens
{
    my ($self) = @_;

    return map { PLS::Parser::Element->new(file => $self->{file}, element => $_) } $self->{ppi_element}->tokens;
}

1;
