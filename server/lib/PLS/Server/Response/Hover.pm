package PLS::Server::Response::Hover;
use parent q(PLS::Server::Response);

use strict;
use warnings;

use PLS::Parser::BuiltIns;
use Pod::Find;
use Pod::Markdown;

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
    my ($package, $subroutine) =
      PLS::Parser::GoToDefinition::find_subroutine_at_location(@elements, \$line_number,
                                                               \$column_number);
    my $is_class_call = 0;
    unless (length $subroutine)
    {
        ($package, $subroutine) =
          PLS::Parser::GoToDefinition::find_class_calls_at_location(@elements, \$line_number,
                                                                    \$column_number);
        $is_class_call = 1 if (length $subroutine);
    } ## end unless (length $subroutine...)

    if (length $subroutine)
    {
        if (length $package)
        {
            $name = $is_class_call ? "${package}->${subroutine}" : "${package}::${subroutine}";
            my $path = Pod::Find::pod_where({-inc => 1}, $package);

            if (length $path)
            {
                open my $fh, '<', $path;
                my @lines;
                my $start = '';

                while (my $line = <$fh>)
                {
                    if ($line =~ /^=(head\d|item).*\b$subroutine\b.*$/)
                    {
                        $start = $1;
                        push @lines, $line;
                        next;
                    } ## end if ($line =~ /^=(head\d|item).*\b$subroutine\b.*$/...)

                    if (length $start)
                    {
                        push @lines, $line;

                        if (   $start eq 'item' and $line =~ /^=item/
                            or $start =~ /head/ and $line =~ /^=head/
                            or $line =~ /^=cut/)
                        {
                            last;
                        }
                    } ## end if (length $start)
                } ## end while (my $line = <$fh>)

                close $fh;

                # we don't want the last line - it's a start of a new section.
                pop @lines;

                if (scalar @lines)
                {
                    my $parser = Pod::Markdown->new();

                    $parser->output_string(\$markdown);
                    $parser->no_whining(1);
                    $parser->parse_lines(@lines, undef);
                    $ok = $parser->content_seen;
                } ## end if (scalar @lines)
            } ## end if (length $path)
        } ## end if (length $package)
        else
        {
            $name = $subroutine;
            $ok =
              PLS::Parser::BuiltIns::get_builtin_function_documentation($subroutine, \$markdown);
        } ## end else [ if (length $package) ]
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
