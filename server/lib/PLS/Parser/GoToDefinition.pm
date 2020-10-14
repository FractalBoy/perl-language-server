package PLS::Parser::GoToDefinition;

use Digest::SHA;
use File::Path;
use File::Spec;
use JSON;
use Perl::Critic::Utils;
use PPI::Cache;
use PPI::Document;
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
        mkdir $cache unless (-d $cache_path);
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
           my @parts = split '::', $element->content;
           my $subroutine = pop @parts;
           my $package = join '::', @parts;
           return ($package, $subroutine);
       }
       else
       {
           return $element->content;
       }
    } ## end foreach my $element (@_)
} ## end sub find_subroutine_at_location

sub find_method_calls_at_location
{
    foreach my $element (@_)
    {
        return $element if is_method_call($element);
    }
}

sub find_class_calls_at_location
{
    foreach my $element (@_)
    {
        if (is_class_method_call($element))
        {
            return ($element->sprevious_sibling->sprevious_sibling->content, $element->content);
        }
    }

    return;
}

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

    @perl_files = @{get_all_perl_files()} unless (scalar @perl_files);

    my @results;

    foreach my $perl_file (@perl_files)
    {
        next if (-l $perl_file);

        # start with a grep since it's faster
        open my $fh, '<', $perl_file or next;
        next unless grep { /sub\s+\Q$subroutine\E/ } <$fh>;

        index_subroutine_declarations_in_file($perl_file);
        my $index = get_index_for_perl_file($perl_file);
        my ($found) = grep { $_->{name} eq $subroutine } @{$index->{subs}};
        next unless ref $found eq 'HASH';

        my ($line_number, $column_number) = @{$found->{location}}{qw(line_number column_number)};
        $line_number--; $column_number--;

        push @results,  {
                uri   => URI::file->new($perl_file)->as_string,
                range => {
                          start => {
                                    line      => $line_number,
                                    character => $column_number
                                   },
                          end => {
                                  line      => $line_number,
                                  character => ($column_number + length 'sub ' + length $found->{content})
                                 }
                         }
              };
    }

    return \@results;
} ## end sub search_files_for_subroutine_declaration

sub get_all_perl_files
{
    my @perl_files;

    return unless (length $PLS::Server::State::ROOT_PATH);

    File::Find::find(
        sub {
            return unless -f;
            my @pieces = File::Spec->splitdir($File::Find::name);

            # exclude hidden files and files in hidden directories
            return if grep { /^\./ } @pieces;
            push @perl_files, $File::Find::name if (/\.p[ml]$/);
            open my $code, '<', $File::Find::name or return;
            my $first_line = <$code>;
            push @perl_files, $File::Find::name if ($first_line =~ /^#!.*perl$/);
            close $code;
        },
        $PLS::Server::State::ROOT_PATH
                    );

    return \@perl_files;
} ## end sub get_all_perl_files

sub index_subroutine_declarations_in_file
{
    my ($perl_file) = @_;

    my $relative = File::Spec->abs2rel($perl_file, $PLS::Server::State::ROOT_PATH);
    my $cache_file = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_cache', $relative);
    my (undef, $cache_file_parent_dir) = File::Spec->splitpath($cache_file);
    File::Path::make_path($cache_file_parent_dir);

    my $sha = Digest::SHA->new(256);
    $sha->addfile($perl_file, 'U');
    my $checksum = $sha->hexdigest;

    if (-f $cache_file)
    {
        my $obj = get_index_for_perl_file($cache_file);
        return if $obj->{checksum} eq $checksum;
    }

    my %cache_obj = (
        checksum => $checksum,
        subs => []
    );

    my $document = PPI::Document->new($perl_file);
    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Sub') });
    return unless $find->start($document);

    while (my $match = $find->match)
    {
        push @{$cache_obj{subs}}, {
            location => {
                line_number => $match->line_number,
                column_number => $match->column_number
            },
            name => $match->name
        };
    }

    open my $fh, '>', $cache_file or return;
    my $json = encode_json \%cache_obj;
    print {$fh} $json;
    $PLS::Server::State::FILE_CACHE{$perl_file} = \%cache_obj;
}

sub get_index_for_perl_file
{
    my ($perl_file) = @_;

    my $relative = File::Spec->abs2rel($perl_file, $PLS::Server::State::ROOT_PATH);
    my $cache_file = File::Spec->catfile($PLS::Server::State::ROOT_PATH, '.pls_cache', $relative);

    my $cached = $PLS::Server::State::FILE_CACHE{$perl_file};
    my $json = encode_json $cached;

    my $sha = Digest::SHA->new(256);
    $sha->add($json);
    my $cache_checksum = $sha->hexdigest;

    $sha = Digest::SHA->new(256);
    $sha->add($cache_file);
    my $file_checksum = $sha->hexdigest;

    return $cached if ($cache_checksum eq $file_checksum);

    open my $fh, '<', $cache_file or return {};
    my $json = do { local $/; <$fh> };
    my $data = decode_json $json;
    $PLS::Server::State::FILE_CACHE{$perl_file} = $data;
    return $data;
}

1;
