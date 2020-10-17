package PLS::Parser::GoToDefinition;

use strict;
use warnings;

use Digest::SHA;
use File::Path;
use File::Spec;
use File::stat;
use JSON;
use List::Util qw(all);
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
        my $subroutine = $method->content =~ s/SUPER:://r;
        return search_files_for_subroutine_declaration($subroutine);
    }
    if (my ($class, $method) = find_class_calls_at_location(@matches))
    {
        return search_for_package_subroutine($class, $method);
    }
    if (my $package = find_package_at_location(@matches))
    {
        return search_for_package($package);
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

sub find_package_at_location
{
    foreach my $element (@_)
    {
        if (my $name = is_package($element))
        {
            return $name;
        }
    }
}

sub is_class_method_call
{
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless (ref $element->sprevious_sibling eq 'PPI::Token::Operator' and $element->sprevious_sibling eq '->');
    return (ref $element->sprevious_sibling->sprevious_sibling eq 'PPI::Token::Word');
} ## end sub is_class_method_call

sub is_method_call
{
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless (ref $element->sprevious_sibling eq 'PPI::Token::Operator' and $element->sprevious_sibling eq '->');
    return (ref $element->sprevious_sibling->sprevious_sibling and ref $element->sprevious_sibling->sprevious_sibling ne 'PPI::Token::Word');
} ## end sub is_method_call

sub is_package
{
    my ($element) = @_;
    return $element->module if ($element->isa('PPI::Statement::Include') and $element->type eq 'use');
    return $element->content if ($element->isa('PPI::Token::Word') and ref $element->snext_sibling eq 'PPI::Token::Operator' and $element->snext_sibling eq '->');
    return;
}

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

#    foreach my $dir (@INC)
#    {
#        my $potential_path = File::Spec->join($dir, @path) . '.pm';
#        next unless (-f $potential_path);
#        return search_files_for_subroutine_declaration($subroutine, $potential_path);
#    } ## end foreach my $dir (@INC)
} ## end sub search_for_package_subroutine

sub search_for_package
{
    my ($package, @perl_files) = @_;

    index_declarations(@perl_files);
    my $index = get_index();
    my $found = $index->{packages}{$package};
    return [] unless (ref $found eq 'ARRAY');

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
                              character => ($column_number + length $package)
                             }
                     }
          };
    } ## end foreach my $location (@locations...)

    return \@results;
}

sub search_files_for_subroutine_declaration
{
    my ($subroutine, @perl_files) = @_;

    index_declarations(@perl_files);
    my $index = get_index();
    my $found = $index->{subs}{$subroutine};
    return [] unless (ref $found eq 'ARRAY');

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
        $PLS::Server::State::ROOT_PATH, @INC
                    );

    return \@perl_files;
} ## end sub get_all_perl_files

sub get_index
{
    my $index_file = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_cache', 'index');
    return {} unless -f $index_file;
    my $mtime = (stat $index_file)->mtime;
    $PLS::Server::State::INDEX_LAST_MTIME = 0 unless (length $PLS::Server::State::INDEX_LAST_MTIME);
    return $PLS::Server::State::INDEX if $mtime <= $PLS::Server::State::INDEX_LAST_MTIME;
    $PLS::Server::State::INDEX_LAST_MTIME = $mtime;
    $PLS::Server::State::INDEX = Storable::retrieve($index_file);
    return $PLS::Server::State::INDEX;
}

sub index_declarations
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
        return $index if (all { $_ <= $index_mtime } @mtimes);
        @perl_files = grep { (stat $_)->mtime > $index_mtime } @perl_files;
    } ## end if (-f $index_file)

    foreach my $perl_file (@perl_files)
    {
        my $document = PPI::Document->new($perl_file);
        next unless (ref $document eq 'PPI::Document');
        $document->index_locations;

        update_index_for_subroutines($perl_file, $document, $index);
        update_index_for_packages($perl_file, $document, $index);
    } ## end foreach my $perl_file (@perl_files...)

    Storable::nstore($index, $index_file);
    $PLS::Server::State::INDEX = $index;
    $PLS::Server::State::INDEX_LAST_MTIME = (stat $index_file)->mtime;
} ## end sub index_subroutine_declarations

sub update_index_for_subroutines
{
    my ($perl_file, $document, $index) = @_;

    my @subroutines = (@{get_subroutines_in_file($document)}, @{get_constants_in_file($document)});

    if (ref $index->{files}{$perl_file}{subs} eq 'ARRAY')
    {
        # remove any old references
        my @subs_to_remove = grep { my $sub = $_; all { $_->{name} ne $sub } @subroutines } @{$index->{files}{$perl_file}{subs}};

        foreach my $sub (@subs_to_remove)
        {
            @{$index->{subs}{$sub}} = grep { $_->{file} ne $perl_file } @{$index->{subs}{$sub}};
            delete $index->{subs}{$sub} unless (scalar @{$index->{subs}{$sub}});
        } ## end foreach my $key (keys %{$index...})

        @{$index->{files}{$perl_file}{subs}} = ();
    }
    else
    {
        $index->{files}{$perl_file}{subs} = [];
    }

    # add references for this file back in
    foreach my $subroutine (@subroutines)
    {
        my %sub_info = (file => $perl_file, location => $subroutine->{location});

        if (ref $index->{subs}{$subroutine->{name}} eq 'ARRAY')
        {
            push @{$index->{subs}{$subroutine->{name}}}, \%sub_info;
        }
        else
        {
            $index->{subs}{$subroutine->{name}} = [\%sub_info];
        }

        push @{$index->{files}{$perl_file}{subs}}, $subroutine->{name};
    } ## end foreach my $subroutine (keys...)
}

sub update_index_for_packages
{
    my ($perl_file, $document, $index) = @_;

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Package') });
    return unless $find->start($document);

    my @packages;

    while (my $match = $find->match)
    {
        push @packages, {
            name => $match->namespace,
            location => {
                line_number => $match->line_number,
                column_number => $match->column_number
            }
        };
    }

    if (ref $index->{files}{$perl_file}{packages} eq 'ARRAY')
    {
        # remove any old references
        my @packages_to_remove = grep { my $pack = $_; all { $_->{name} ne $pack } @packages } @{$index->{files}{$perl_file}{subs}};

        foreach my $pack (@packages_to_remove)
        {
            @{$index->{packages}{$pack}} = grep { $_->{file} ne $perl_file } @{$index->{packages}{$pack}};
            delete $index->{packages}{$pack} unless (scalar @{$index->{packages}{$pack}});
        } ## end foreach my $key (keys %{$index...})

        @{$index->{files}{$perl_file}{packages}} = ();
    }
    else
    {
        $index->{files}{$perl_file}{packages} = [];
    }

    foreach my $package (@packages)
    {
        my %package_info = (file => $perl_file, location => $package->{location});

        if (ref $index->{packages}{$package->{name}} eq 'ARRAY')
        {
            push @{$index->{packages}{$package->{name}}}, \%package_info;
        }    
        else
        {
            $index->{packages}{$package->{name}} =  [\%package_info];
        }

        push @{$index->{files}{$perl_file}{packages}}, $package->{name};
    }
}

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
