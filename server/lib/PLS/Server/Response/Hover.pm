package PLS::Server::Response::Hover;
use parent q(PLS::Server::Response);

use strict;
use warnings;

use PLS::Parser::BuiltIns;

sub new
{
    my ($class, $request) = @_;

    my $document =
      PLS::Parser::GoToDefinition::document_from_uri($request->{params}{textDocument}{uri});
    my ($line, $column) =
      PLS::Parser::GoToDefinition::ppi_location($request->{params}{position}{line},
                                                $request->{params}{position}{character});
    my @elements =
      PLS::Parser::GoToDefinition::find_elements_at_location($document, $line, $column);

    my ($ok, $name, $markdown, $line_number, $column_number);

    if (
        my ($package, $subroutine) =
        PLS::Parser::GoToDefinition::find_subroutine_at_location(
                                                           @elements, \$line_number, \$column_number
                                                                )
       )
    {
        unless (length $package)
        {
            $name = $subroutine;
            $ok =
              PLS::Parser::BuiltIns::get_builtin_function_documentation($subroutine, \$markdown);
        } ## end unless (length $package)
    } ## end if (my ($package, $subroutine...))

    unless ($ok)
    {
        if (
            my $variable =
            PLS::Parser::GoToDefinition::find_variable_at_location(
                                                           @elements, \$line_number, \$column_number
                                                                  )
           )
        {
            $name = $variable;
            $ok = PLS::Parser::BuiltIns::get_builtin_variable_documentation($variable, \$markdown);
        } ## end if (my $variable = PLS::Parser::GoToDefinition::find_variable_at_location...)
    } ## end unless ($ok)

    $line_number--;
    $column_number-- if $ok;

    my $result;

    if ($ok)
    {
        $line_number--;
        $column_number--;
        $result = {
                   contents => {kind => 'markdown', value => $markdown},
                   range    => {
                             start => {
                                       line      => $line_number,
                                       character => $column_number,
                                      },
                             end => {
                                     line      => $line_number,
                                     character => ($column_number + length $name),
                                    }
                            }
                  };
    } ## end if ($ok)

    my %self = (
                id     => $request->{id},
                result => $result
               );

    return bless \%self, $class;
} ## end sub new

1;
