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

sub name
{
    my ($self) = @_;

    return $self->{ppi_element}->content;
}

sub package_name
{
    my ($self) = @_;

    my $element = $self->{ppi_element};

    if (    $element->isa('PPI::Token::Quote::Literal')
        and $element->parent->isa('PPI::Statement::Include')
        and $element->parent->type eq 'use'
        and $element->parent->module eq 'parent')
    {
        return $element->literal;
    } ## end if ($element->isa('PPI::Token::Quote::Literal'...))
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

    my $previous_sibling = PLS::Parser::Element->new(file => $self->{file}, element => $self->{ppi_element}->sprevious_sibling);
    return $previous_sibling;
} ## end sub previous_sibling

1;
