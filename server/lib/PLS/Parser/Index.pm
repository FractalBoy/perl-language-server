package PLS::Parser::Index;

use strict;
use warnings;
use feature 'state';

use File::Find;
use File::stat;
use File::Spec;
use IO::Async::Function;
use IO::Async::Loop;
use URI::file;
use List::Util qw(any);
use Path::Tiny;
use POSIX;
use PPR;
use Storable;
use Time::Piece;

use PLS::Parser::Document;

=head1 NAME

PLS::Parser::Index

=head1 DESCRIPTION

This class caches and stores indexed data about the workspace.
It is used for quick searching of subroutines and packages by name.

=cut

sub new
{
    my ($class, @args) = @_;

    state $self;
    return $self if (ref $self eq 'PLS::Parser::Index');

    my %args = @args;
    $self = bless {
                      workspace_folders => $args{workspace_folders},
                      cache => {},
                     }, $class;

    return $self;
} ## end sub new

sub start_indexing_function
{
    my ($self) = @_;

    return if (ref $self->{indexing_function} eq 'IO::Async::Function');

    $self->{indexing_function} = IO::Async::Function->new(code => \&_index_files);

    my $loop = IO::Async::Loop->new();
    $loop->add($self->{indexing_function});

    return;
} ## end sub start_indexing_function

sub _index_files
{
    my ($file) = @_;

    my $text         = PLS::Parser::Document::text_from_uri(URI::file->new($file)->as_string());
    my $line_offsets = PLS::Parser::Index->get_line_offsets($text);
    my $packages     = PLS::Parser::Index->get_packages($text, $file, $line_offsets);
    my $subroutines  = PLS::Parser::Index->get_subroutines($text, $file, $line_offsets);

    return $packages, $subroutines;
}

sub index_files
{
    my ($self, @files) = @_;

    $self->start_indexing_function();

    @files = @{$self->get_all_perl_files()} unless (scalar @files);

    foreach my $file (@files)
    {
        $self->{indexing_function}->call(
            args      => [$file],
            on_result => sub {
                my ($result, $packages, $subs) = @_;

                return if ($result ne 'return');

                foreach my $type (qw(subs packages))
                {
                    $self->cleanup_index($type, $file);
                } ## end foreach my $type (qw(subs packages)...)

                foreach my $ref (keys %{$packages})
                {
                    push @{$self->{cache}{packages}{$ref}}, @{$packages->{$ref}};
                    push @{$self->{cache}{files}{$file}{packages}}, $ref;
                }

                foreach my $ref (keys %{$subs})
                {
                    push @{$self->{cache}{subs}{$ref}}, @{$subs->{$ref}};
                    push @{$self->{cache}{files}{$file}{subs}}, $ref;
                }

                return;
            }
        );
    }

    return;
} ## end sub index_files

sub deindex_workspace
{
    my ($self, $path) = @_;

    @{$self->{workspace_folders}} = grep { $_ ne $path } @{$self->{workspace_folders}};

    foreach my $file (keys %{$self->{cache}{files}})
    {
        next unless path($path)->subsumes($file);

        foreach my $type (qw(subs packages))
        {
            $self->cleanup_index($type, $file);
        }
    }

    return;
}

sub index_workspace
{
    my ($self, $path) = @_;

    push @{$self->{workspace_folders}}, $path;    

    my @workspace_files = @{$self->get_all_perl_files($path)};
    $self->index_files(@workspace_files);

    return;
}

sub cleanup_index
{
    my ($self, $type, $file) = @_;

    my $index = $self->{cache};

    if (ref $index->{files}{$file}{$type} eq 'ARRAY')
    {
        foreach my $ref (@{$index->{files}{$file}{$type}})
        {
            @{$index->{$type}{$ref}} = grep { $_->{uri} ne URI::file->new($file)->as_string() } @{$index->{$type}{$ref}};
            delete $index->{$type}{$ref} unless (scalar @{$index->{$type}{$ref}});
        }

        @{$index->{files}{$file}{$type}} = ();
    } ## end if (ref $index->{files...})
    else
    {
        $index->{files}{$file}{$type} = [];
    }

    return;
} ## end sub cleanup_index

sub cleanup_old_files
{
    my ($self) = @_;

    my $index = $self->{cache};

    if (ref $index->{files} eq 'HASH')
    {
        foreach my $file (keys %{$index->{files}})
        {
            next if -f $file;

            if (ref $index->{subs} eq 'HASH')
            {
                foreach my $sub (@{$index->{files}{$file}{subs}})
                {
                    next unless (ref $index->{subs}{$sub} eq 'ARRAY');
                    @{$index->{subs}{$sub}} = grep { $_->{uri} eq URI::file->new($file)->as_string() } @{$index->{subs}{$sub}};
                    delete $index->{subs}{$sub} unless (scalar @{$index->{subs}{$sub}});
                } ## end foreach my $sub (@{$index->...})
            } ## end if (ref $index->{subs}...)

            if (ref $index->{packages} eq 'HASH')
            {
                foreach my $package (@{$index->{files}{$file}{packages}})
                {
                    next unless (ref $index->{packages}{$package} eq 'ARRAY');
                    @{$index->{packages}{$package}} = grep { $_->{uri} eq URI::file->new($file)->as_string() } @{$index->{packages}{$package}};
                    delete $index->{packages}{$package} unless (scalar @{$index->{packages}{$package}});
                } ## end foreach my $package (@{$index...})
            } ## end if (ref $index->{packages...})

            delete $index->{files}{$file};
        } ## end foreach my $file (keys %{$index...})
    } ## end if (ref $index->{files...})

    foreach my $type (keys %{$index})
    {
        my $refs_cleaned = 0;

        foreach my $ref (keys %{$index->{$type}})
        {
            next unless (ref $index->{$type}{$ref} eq 'ARRAY');
            my $count_before = scalar @{$index->{$type}{$ref}};
            @{$index->{$type}{$ref}} = grep { -e URI->new($_->{uri})->file } @{$index->{$type}{$ref}};
            my $count_after = scalar @{$index->{$type}{$ref}};
            $refs_cleaned++ if ($count_after < $count_before);
        } ## end foreach my $ref (keys %{$index...})
    } ## end foreach my $type (keys %{$index...})

    return;
} ## end sub cleanup_old_files

sub find_package_subroutine
{
    my ($self, $package, $subroutine) = @_;

    my $index     = $self->{cache};
    my $locations = $index->{packages}{$package};

    if (ref $locations ne 'ARRAY')
    {
        my $external = PLS::Parser::Document->find_external_subroutine($package, $subroutine);
        return [$external] if (ref $external eq 'HASH');
        return [];
    } ## end if (ref $locations ne ...)

    foreach my $file (@{$locations})
    {
        return $self->find_subroutine($subroutine, $file->{uri});
    }

    return;
} ## end sub find_package_subroutine

sub find_subroutine
{
    my ($self, $subroutine, @uris) = @_;

    my $index = $self->{cache};
    my $found = $index->{subs}{$subroutine};
    return [] unless (ref $found eq 'ARRAY');

    my @locations = @$found;

    if (scalar @uris)
    {
        @locations = grep {
            my $location = $_;
            scalar grep { $location->{uri} eq $_ } @uris;
        } @locations;
    } ## end if (scalar @uris)

    return Storable::dclone(\@locations);
} ## end sub find_subroutine

sub find_package
{
    my ($self, $package) = @_;

    my $index = $self->{cache};
    my $found = $index->{packages}{$package};

    if (ref $found ne 'ARRAY')
    {
        my $external = PLS::Parser::Document->find_external_package($package);
        return [$external] if (ref $external eq 'HASH');
        return [];
    } ## end if (ref $found ne 'ARRAY'...)

    return Storable::dclone($found);
} ## end sub find_package

sub get_ignored_files
{
    my ($self) = @_;

    my @ignored_files;

    foreach my $workspace_folder (@{$self->{workspace_folders}})
    {
        my $plsignore = File::Spec->catfile($workspace_folder, '.plsignore');
        next if (not -f $plsignore or not -r $plsignore);

        my $mtime = stat($plsignore)->mtime;
        next if (length $self->{ignore_files_mtimes}{$plsignore} and $self->{ignore_file_mtimes}{$plsignore} >= $mtime);

        open my $fh, '<', $plsignore or next;

        $self->{ignored_files}{$plsignore} = [];
        $self->{ignore_file_mtimes}{$plsignore} = $mtime;

        while (my $line = <$fh>)
        {
            chomp $line;
            push @{$self->{ignored_files}{$plsignore}}, glob File::Spec->catfile($workspace_folder, $line);
        }

        @{$self->{ignored_files}{$plsignore}} = map { path($_)->realpath } @{$self->{ignored_files}{$plsignore}};
    }

    return [map { @{$self->{ignored_files}{$_}} } keys %{$self->{ignored_files}}];
} ## end sub get_ignored_files

sub get_all_subroutines
{
    my ($self) = @_;

    return [] if (ref $self->{cache}{subs} ne 'HASH');
    return [keys %{$self->{cache}{subs}}];
} ## end sub get_all_subroutines

sub get_all_packages
{
    my ($self) = @_;

    return [] if (ref $self->{cache}{packages} ne 'HASH');
    return [keys %{$self->{cache}{packages}}];
} ## end sub get_all_packages

sub is_ignored
{
    my ($self, $file) = @_;

    my @ignore_files = @{$self->get_ignored_files()};
    return if not scalar @ignore_files;

    my $real_path = path($file)->realpath;

    return 1 if any { $_ eq $real_path } @ignore_files;
    return 1 if any { $_->subsumes($real_path) } @ignore_files;

    return;
} ## end sub is_ignored

sub get_all_perl_files
{
    my ($self, @folders) = @_;

    @folders = @{$self->{workspace_folders}} unless (scalar @folders);
    return [] unless (scalar @folders);

    my @perl_files;

    File::Find::find(
        {
         preprocess => sub {
             return () if $self->is_ignored($File::Find::dir);
             return grep { not $self->is_ignored($_) } @_;
         },
         wanted => sub {
             return unless $self->is_perl_file($File::Find::name);
             my @pieces = File::Spec->splitdir($File::Find::name);

             # exclude hidden files and files in hidden directories
             return if any { /^\./ } @pieces;

             push @perl_files, $File::Find::name;
         }
        },
        @folders
                    );

    return \@perl_files;
} ## end sub get_all_perl_files

sub is_perl_file
{
    my ($class, $file) = @_;

    return if -l $file;
    return unless -f $file;
    return if any { /^\.pls-tmp/ } grep { length } File::Spec->splitdir($file);
    return if $file =~ /\.t$/;

    return 1 if $file =~ /\.p[lm]$/;
    open my $fh, '<', $file or return;
    my $first_line = <$fh>;
    close $fh;
    return 1 if (length $first_line and $first_line =~ /^\s*#!.*perl$/);
    return;
} ## end sub is_perl_file

sub log
{
    my (undef, $message) = @_;

    my $time = Time::Piece->new;
    $time = $time->ymd . ' ' . $time->hms;
    print {\*STDERR} "[$time] $message\n";

    return;
} ## end sub log

sub get_line_offsets
{
    my ($class, $text) = @_;

    my @line_offsets = (0);

    while ($$text =~ /\r?\n/g)
    {
        push @line_offsets, pos($$text);
    }

    return \@line_offsets;
} ## end sub get_line_offsets

sub get_line_by_offset
{
    my ($class, $line_offsets, $offset) = @_;

    for (my $i = 0 ; $i <= $#{$line_offsets} ; $i++)
    {
        my $current_offset = $line_offsets->[$i];
        my $next_offset    = $i + 1 <= $#{$line_offsets} ? $line_offsets->[$i + 1] : undef;

        if ($current_offset <= $offset and (not defined $next_offset or $next_offset > $offset))
        {
            return $i;
        }
    } ## end for (my $i = 0 ; $i <= ...)

    return $#{$line_offsets};
} ## end sub get_line_by_offset

sub get_packages
{
    my ($class, $text, $file, $line_offsets) = @_;

    state $rx = qr/((?&PerlPackageDeclaration))$PPR::GRAMMAR/x;
    my %packages;

    while ($$text =~ /$rx/g)
    {
        my $name = $1;

        my $end        = pos($$text);
        my $start      = $end - length $name;
        my $start_line = $class->get_line_by_offset($line_offsets, $start);
        $start -= $line_offsets->[$start_line];
        my $end_line = $class->get_line_by_offset($line_offsets, $end);
        $end -= $line_offsets->[$end_line];

        $name =~ s/package//;
        $name =~ s/^\s+|\s+$//g;
        $name =~ s/;$//g;

        my $uri = URI::file->new($file)->as_string();

        push @{$packages{$name}},
          {
            uri   => $uri,
            range => {
                      start => {
                                line      => $start_line,
                                character => $start
                               },
                      end => {
                              line      => $end_line,
                              character => $end
                             }
                     }
          };
    } ## end while ($$text =~ /$rx/g)

    return \%packages;
} ## end sub get_packages

sub get_subroutines
{
    my ($class, $text, $file, $line_offsets) = @_;

    state $sub_rx   = qr/((?&PerlSubroutineDeclaration))$PPR::GRAMMAR/;
    state $sig_rx   = qr/(?<label>(?<params>(?&PerlVariableDeclaration))(?&PerlOWS)=(?&PerlOWS)\@_)$PPR::GRAMMAR/;
    state $var_rx   = qr/((?&PerlVariable))$PPR::GRAMMAR/;
    my %subroutines;

    my $uri = URI::file->new($file)->as_string();

    while ($$text =~ /$sub_rx/g)
    {
        my $name = $1;
        my $end  = pos($$text);

        my $start = $end - length $name;

        my $start_line = $class->get_line_by_offset($line_offsets, $start);
        $start -= $line_offsets->[$start_line];
        my $end_line = $class->get_line_by_offset($line_offsets, $end);
        $end -= $line_offsets->[$end_line];

        my $signature;
        my @parameters;

        if ($name =~ /$sig_rx/)
        {
            $signature = $+{label};
            my $parameters = $+{params};
            while ($parameters =~ /$var_rx/g)
            {
                push @parameters, {label => $1};
            }
        } ## end if ($block =~ /$sig_rx/...)

        ($name) = $name =~ /(?:sub\s+)?(\S+)\s*[;{]/;
        $name =~ s/\([^)]*+\)//;
        $name =~ s/^\s+|\s+$//g;

        push @{$subroutines{$name}},
          {
            uri   => $uri,
            range => {
                      start => {
                                line      => $start_line,
                                character => $start
                               },
                      end => {
                              line      => $end_line,
                              character => $end
                             }
                     },
            signature => {label => $signature, parameters => \@parameters}
          };
    } ## end while ($$text =~ /$sub_rx/g...)

    return \%subroutines;
} ## end sub get_subroutines

1;
