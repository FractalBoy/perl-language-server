package PLS::Parser::GoToDefinition;

use File::Spec;
use Perl::Critic::Utils;
use PPI::Cache;
use PPI::Document;
use PPI::Find;
use URI;
use URI::file;
use Data::Dumper;

use PLS::Server::State;

sub document_from_uri {
    my ($uri) = @_;

    if (length $PLS::Server::State::ROOT_PATH)
    {
        my $cache_path = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_cache');
        mkdir $cache unless (-d $cache_path);
        my $ppi_cache = PPI::Cache->new(path => $cache_path);
        PPI::Document->set_cache($ppi_cache);
    }

    my $file = URI->new($uri);
    my $document = PPI::Document->new($file->file);
    $document->index_locations;

    return $document;
}

sub lsp_location {
    my ($element) = @_;

    return ($element->line_number - 1, $element->column_number - 1);
}

sub ppi_location {
    my ($line, $column) = @_;

    # LSP defines position as 0-indexed, PPI defines it 1-indexed
    return (++$line, ++$column);
}

sub go_to_definition {
    my ($document, $line, $column) = @_;

    ($line, $column) = ppi_location($line, $column);
    my @matches = find_elements_at_location($document, $line, $column);

    if (my $subroutine = find_subroutine_at_location(@matches))
    {
        return search_files_for_subroutine_declaration($subroutine->content);
    }
    if (my $method = find_method_calls_at_location(@matches))
    {
        return search_files_for_subroutine_declaration($method->content);
    }
    if (my ($class, $method) = find_class_calls_at_location(@matches))
    {
        return search_for_package_subroutine($class, $method);
    }

    return;
}

sub find_elements_at_location {
    my ($document, $line, $column) = @_;

    my $find = PPI::Find->new(sub {
        my ($element) = @_;

        $element->line_number == $line &&
        $element->column_number <= $column &&
        $element->column_number + length($element->content) >= $column;
    });

    return unless $find->start($document);

    my @matches;
    while (my $match = $find->match) {
        push @matches, $match;
    }

    return @matches;
}

sub find_subroutine_at_location {
    foreach my $element (@_) {
        return $element if element_is_subroutine_name($element);

        if ($element->isa('PPI::Token::Cast')) {
            my $sibling = $element;
            while ($sibling = $sibling->next_sibling) {
                return $sibling if element_is_subroutine_name($sibling);
            }
        }
    }
}

sub find_method_calls_at_location
{
    return grep { is_method_call($_) } @_;
}

sub find_class_calls_at_location
{
    return grep { is_class_method_call($_) } @_;
}

sub element_is_subroutine_name {
    my ($element) = @_;

    return $element->isa('PPI::Token::Word') &&
        (
            is_subroutine_name($element) ||
            Perl::Critic::Utils::is_function_call($element)
        ) ||
        $element->isa('PPI::Token::Symbol') &&
        $element =~ /^&/ &&
        $element !~ /^\$/;
}

sub is_subroutine_name {
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return $element->sprevious_sibling eq 'sub' && $element->parent->isa('PPI::Statement');
}

sub is_class_method_call {
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless $element->sprevious_sibling->isa('PPI::Token::Operator') && $element->sprevious_sibling eq '->';
    return unless $element->sprevious_sibling->sprevious_sibling->isa('PPI::Token::Word');

    my $class = $element->sprevious_sibling->sprevious_sibling;
    my $method = $element;
    return ($class, $method);
}

sub is_method_call {
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless $element->sprevious_sibling->isa('PPI::Token::Operator') && $element->sprevious_sibling eq '->';
    return $element->sprevious_sibling->sprevious_sibling->isa('PPI::Token::Symbol');
}

sub search_for_package_subroutine
{
    my ($class, $subroutine) = @_;

    my @path = split ':', $subroutine;
    my $package_path = join '/', @path;
    $package_path .= '.pm';
    my $perl_files = get_all_perl_files();

    foreach my $perl_file (@$perl_files)
    {
        if ($perl_file =~ /\Q$package_path\E$/)
        {
            return search_files_for_subroutine_declaration($subroutine, $perl_file)
        }
    }

    foreach my $dir (@INC)
    {
        my $potential_path = File::Spec->catfile($dir, @path);
        next unless (-f $potential_path);
        return search_files_for_subroutine_declaration($subroutine, $potential_path);
    }
}

sub search_files_for_subroutine_declaration
{
    my ($subroutine, @perl_files) = @_;

    @perl_files = @{get_all_perl_files()} unless (scalar @perl_files);

    my $find = PPI::Find->new(sub {
        my ($element) = @_;
        return 0 unless is_subroutine_name($element);
        return $element->content eq $subroutine;
    });

    my @results;

    foreach my $perl_file (@perl_files)
    {
        my $document = PPI::Document->new($perl_file);
        next unless $find->start($document);

        while (my $match = $find->match)
        {
            my ($line_number, $column_number) = lsp_location($match);

            push @results, {
                uri => URI::file->new($perl_file)->as_string,
                range => {
                    start => {
                        line => $line_number,
                        character => $column_number
                    },
                    end => {
                        line => $line_number,
                        character => ($column_number + length $match->content)
                    }
                }
            }
        }
    }

    return \@results;
}

sub get_all_perl_files
{
    my @perl_files;

    return unless (length $PLS::Server::State::ROOT_PATH);

    File::Find::find(sub {
        return unless -f;
        my @pieces = File::Spec->splitdir($File::Find::name);
        # exclude hidden files and files in hidden directories
        return if grep { /^\./ } @pieces;
        push @perl_files, $File::Find::name if (/\.p[ml]$/);
        open my $code, '<', $File::Find::name or return;
        my $first_line = <$code>;
        push @perl_files, $File::Find::name if ($first_line =~ /^#!.*perl$/);
        close $code;
    }, $PLS::Server::State::ROOT_PATH);


    return \@perl_files;
}

1;
