package PLS::Parser::GoToDefinition;

use strict;
use warnings;

use Digest::SHA;
use File::Path;
use File::Spec;
use File::stat;
use JSON;
use Perl::Critic::Utils ();
use PPI;
use PPI::Cache;
use PPI::Find;
use URI;
use URI::file;

use PLS::Server::State;

sub document_from_uri
{
    my ($uri) = @_;

    if (length $PLS::Server::State::ROOT_PATH)
    {
        my $cache_path = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_ppi_cache');
        mkdir $cache_path unless (-d $cache_path);
        my $ppi_cache = PPI::Cache->new(path => $cache_path);
        PPI::Document->set_cache($ppi_cache);
    } ## end if (length $PLS::Server::State::ROOT_PATH...)

    my $file     = URI->new($uri);
    my $document = PPI::Document->new($file->file);
    $document->index_locations;

    return $document;
} ## end sub document_from_uri

sub lsp_location
{
    my ($element) = @_;

    return ($element->line_number - 1, $element->column_number - 1);
}

sub ppi_location
{
    my ($line, $column) = @_;

    # LSP defines position as 0-indexed, PPI defines it 1-indexed
    return (++$line, ++$column);
} ## end sub ppi_location

sub go_to_definition
{
    my ($document, $line, $column) = @_;

    ($line, $column) = ppi_location($line, $column);
    my @matches = find_elements_at_location($document, $line, $column);

    if (my ($package, $subroutine) = find_subroutine_at_location(@matches))
    {
        if (length $package)
        {
            return search_for_package_subroutine($package, $subroutine);
        }

        return search_files_for_subroutine_declaration($subroutine);
    } ## end if (my ($package, $subroutine...))
    if (my $method = find_method_calls_at_location(@matches))
    {
        return search_files_for_subroutine_declaration($method->content);
    }
    if (my ($class, $method) = find_class_calls_at_location(@matches))
    {
        return search_for_package_subroutine($class, $method);
    }

    return;
} ## end sub go_to_definition

sub find_elements_at_location
{
    my ($document, $line, $column) = @_;

    my $find = PPI::Find->new(
        sub {
            my ($element) = @_;

            $element->line_number == $line
              && $element->column_number <= $column
              && $element->column_number + length($element->content) >= $column;
        }
    );

    return unless $find->start($document);

    my @matches;
    while (my $match = $find->match)
    {
        push @matches, $match;
    }

    return @matches;
} ## end sub find_elements_at_location

sub find_subroutine_at_location
{
    foreach my $element (@_)
    {
        next unless Perl::Critic::Utils::is_function_call($element);
        next unless $element->isa('PPI::Token::Word');

        if ($element->content =~ /::/)
        {
            my @parts      = split '::', $element->content;
            my $subroutine = pop @parts;
            my $package    = join '::', @parts;
            return ($package, $subroutine);
        } ## end if ($element->content ...)
        else
        {
            return ('', $element->content);
        }
    } ## end foreach my $element (@_)

    return;
} ## end sub find_subroutine_at_location

sub find_method_calls_at_location
{
    foreach my $element (@_)
    {
        return $element if is_method_call($element);
    }
} ## end sub find_method_calls_at_location

sub find_class_calls_at_location
{
    foreach my $element (@_)
    {
        if (is_class_method_call($element))
        {
            return ($element->sprevious_sibling->sprevious_sibling->content, $element->content);
        }
    } ## end foreach my $element (@_)

    return;
} ## end sub find_class_calls_at_location

sub is_class_method_call
{
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless $element->sprevious_sibling->isa('PPI::Token::Operator') && $element->sprevious_sibling eq '->';
    return $element->sprevious_sibling->sprevious_sibling->isa('PPI::Token::Word');
} ## end sub is_class_method_call

sub is_method_call
{
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless $element->sprevious_sibling->isa('PPI::Token::Operator') && $element->sprevious_sibling eq '->';
    return not $element->sprevious_sibling->sprevious_sibling->isa('PPI::Token::Word');
} ## end sub is_method_call

sub search_for_package_subroutine
{
    my ($class, $subroutine) = @_;

    my @path         = split '::', $class;
    my $package_path = File::Spec->join(@path) . '.pm';
    my $perl_files   = get_all_perl_files();

    foreach my $perl_file (@$perl_files)
    {
        if ($perl_file =~ /\Q$package_path\E$/)
        {
            return search_files_for_subroutine_declaration($subroutine, $perl_file);
        }
    } ## end foreach my $perl_file (@$perl_files...)

    foreach my $dir (@INC)
    {
        my $potential_path = File::Spec->join($dir, @path) . '.pm';
        next unless (-f $potential_path);
        return search_files_for_subroutine_declaration($subroutine, $potential_path);
    } ## end foreach my $dir (@INC)
} ## end sub search_for_package_subroutine

sub search_files_for_subroutine_declaration
{
    my ($subroutine, @perl_files) = @_;

    index_subroutine_declarations(@perl_files);
    my $index = get_index();
    my $found = $index->{subs}{$subroutine};
    return [] unless ref $found eq 'ARRAY';

    my @locations = @$found;

    if (scalar @perl_files)
    {
        @locations = grep
        {
            my $location = $_;
            grep { $location->{file} eq $_ } @perl_files
        } @locations;
    } ## end if (scalar @perl_files...)

    my @results;

    foreach my $location (@locations)
    {
        my ($line_number, $column_number) = @{$location->{location}}{qw(line_number column_number)};
        $line_number--;
        $column_number--;

        push @results,
          {
            uri   => URI::file->new($location->{file})->as_string,
            range => {
                      start => {
                                line      => $line_number,
                                character => $column_number
                               },
                      end => {
                              line      => $line_number,
                              character => ($column_number + length('sub ') + length($subroutine))
                             }
                     }
          };
    } ## end foreach my $location (@locations...)

    return \@results;
} ## end sub search_files_for_subroutine_declaration

sub get_all_perl_files
{
    my @perl_files;

    return unless (length $PLS::Server::State::ROOT_PATH);

    File::Find::find(
        sub {
            return unless -f;
            return if -l;
            my @pieces = File::Spec->splitdir($File::Find::name);

            # exclude hidden files and files in hidden directories
            return if grep { /^\./ } @pieces;
            if (/\.p[ml]$/)
            {
                push @perl_files, $File::Find::name;
                return;
            }
            open my $code, '<', $File::Find::name or return;
            my $first_line = <$code>;
            push @perl_files, $File::Find::name if (length $first_line and $first_line =~ /^#!.*perl$/);
            close $code;
        },
        $PLS::Server::State::ROOT_PATH
                    );

    return \@perl_files;
} ## end sub get_all_perl_files

sub get_index
{
    my $index_file = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_cache', 'index');
    return {} unless -f $index_file;
    return Storable::retrieve($index_file);
}

sub index_subroutine_declarations
{
    my (@perl_files) = @_;

    my $index_file = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_cache', 'index');
    my (undef, $index_parent_dir) = File::Spec->splitpath($index_file);
    File::Path::make_path($index_parent_dir);

    @perl_files = @{get_all_perl_files()} unless (scalar @perl_files);
    my $index = get_index();

    if (-f $index_file)
    {
        my @mtimes      = map { (stat $_)->mtime } @perl_files;
        my $index_mtime = (stat $index_file)->mtime;

        # return existing index if all files are older than index
        return $index if (scalar grep { $_ <= $index_mtime } @mtimes == scalar @mtimes);
        @perl_files = grep { (stat $_)->mtime > $index_mtime } @perl_files;
    } ## end if (-f $index_file)

    foreach my $perl_file (@perl_files)
    {
        my $document = PPI::Document->new($perl_file);
        next unless (ref $document eq 'PPI::Document');
        $document->index_locations;
        my %subroutines = map { $_->{name} => $_ } (@{get_subroutines_in_file($document)}, @{get_constants_in_file($document)});

        foreach my $key (keys %{$index->{subs}})
        {
            if (defined $subroutines{$key})
            {
                delete $subroutines{$key};
                next;
            }

            @{$index->{subs}{$key}} = grep { $_ ne $perl_file } @{$index->{subs}{$key}};
        } ## end foreach my $key (keys %{$index...})

        foreach my $subroutine (keys %subroutines)
        {
            my $element  = $subroutines{$subroutine};
            my %sub_info = (file => $perl_file, location => $element->{location});

            if (ref $index->{subs}{$subroutine} eq 'ARRAY')
            {
                push @{$index->{subs}{$subroutine}}, \%sub_info;
            }
            else
            {
                $index->{subs}{$subroutine} = [\%sub_info];
            }
        } ## end foreach my $subroutine (keys...)
    } ## end foreach my $perl_file (@perl_files...)

    Storable::nstore($index, $index_file);
    $PLS::Server::State::FILE_CACHE = $index;
} ## end sub index_subroutine_declarations

sub get_constants
{
    my ($document) = @_;

    my $find = PPI::Find->new(
        sub {
            my ($element) = @_;

            return 0 unless $element->isa('PPI::Statement::Include');
            return   unless $element->type eq 'use';
            return $element->module eq 'constant';
        }
    );

    return [] unless $find->start($document);

    my @constants;

    while (my $match = $find->match)
    {
        my ($constructor) = grep { $_->isa('PPI::Structure::Constructor') } $match->children;

        if (ref $constructor eq 'PPI::Structure::Constructor')
        {
            push @constants, grep { _is_constant($_) }
              map  { $_->children }
              grep { $_->isa('PPI::Statement::Expression') } $constructor->children;
        } ## end if (ref $constructor eq...)
        else
        {
            push @constants, grep { _is_constant($_) } $match->children;
        }
    } ## end while (my $match = $find->...)

    return \@constants;
}

sub get_constants_in_file
{
    my $constants = get_constants(@_);

    return [map { {name => $_->content, location => {line_number => $_->line_number, column_number => $_->column_number}} } @$constants];
} ## end sub get_constants_in_file

sub get_subroutines_in_file
{
    my ($document) = @_;

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Sub') and not $_[0]->isa('PPI::Statement::Scheduled') });
    return [] unless $find->start($document);

    my @subroutines;

    while (my $match = $find->match)
    {
        push @subroutines, $match;
    }

    return [map { {name => $_->name, location => {line_number => $_->line_number, column_number => $_->column_number}} } @subroutines];
} ## end sub get_subroutines_in_file

sub _is_constant
{
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless ref $_->snext_sibling eq 'PPI::Token::Operator';
    return $_->snext_sibling->content eq '=>';
} ## end sub _is_constant

1;
