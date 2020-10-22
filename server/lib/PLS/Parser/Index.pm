package PLS::Parser::Index;

use strict;
use warnings;

use File::Find;
use File::Path;
use File::stat;
use File::Spec;
use FindBin;
use List::Util qw(all);
use Time::Piece;
use Storable;

use constant {INDEX_LOCATION => File::Spec->catfile('.pls_cache', 'index')};

sub new
{
    my ($class, @args) = @_;

    my %args = @args;

    my %self = (
                root       => $args{root},
                location   => File::Spec->catfile($args{root}, INDEX_LOCATION),
                cache      => {},
                last_mtime => 0
               );

    return bless \%self, $class;
} ## end sub new

sub index_files
{
    my ($self, @files) = @_;

    my (undef, $parent_dir) = File::Spec->splitpath($self->{location});
    File::Path::make_path($parent_dir);

    @files = @{$self->get_all_perl_files()} unless (scalar @files);

    my $index = $self->index();

    if (-f $self->{location})
    {
        my @mtimes = map { {file => $_, mtime => (stat $_)->mtime} } @files;

        # return existing index if all files are older than index
        return $index if (all { $_ <= $self->{last_mtime} } @mtimes);
        @files = map { $_->{file} } grep { $_->{mtime} > $self->{last_mtime} } @mtimes;
    } ## end if (-f $self->{location...})

    my $total   = scalar @files;
    my $current = 0;

    foreach my $file (@files)
    {
        $current++;
        my $time = Time::Piece->new;
        $time = $time->ymd . ' ' . $time->hms;
        warn "[$time] Indexing $file ($current/$total)...\n";
        my $document = PLS::Parser::Document->new(path => $file);
        next unless (ref $document eq 'PLS::Parser::Document');

        $self->update_subroutines($index, $document);
        $self->update_packages($index, $document);
    } ## end foreach my $file (@files)

    Storable::nstore($index, $self->{location});
    $self->{cache}      = $index;
    $self->{last_mtime} = (stat $self->{location})->mtime;
} ## end sub index_files

sub index
{
    my ($self) = @_;

    return {} unless -f $self->{location};
    my $mtime = (stat $self->{location})->mtime;
    return $self->{cache} if ($mtime <= $self->{last_mtime});
    $self->{last_mtime} = $mtime;
    $self->{cache}      = Storable::retrieve($self->{location});
    return $self->{cache};
} ## end sub index

sub update_subroutines
{
    my ($self, $index, $document) = @_;

    my $subroutines = $document->get_subroutines();
    my $constants   = $document->get_constants();

    $self->cleanup_index($index, 'subs', $document->{path});
    $self->update_index($index, 'subs', @$subroutines, @$constants);
} ## end sub update_subroutines

sub update_packages
{
    my ($self, $index, $document) = @_;

    my $packages = $document->get_packages();

    $self->cleanup_index($index, 'packages', $document->{path});
    return unless (ref $packages eq 'ARRAY');
    $self->update_index($index, 'packages', @$packages);
} ## end sub update_packages

sub cleanup_index
{
    my ($self, $index, $type, $file) = @_;

    if (ref $index->{files}{$file}{$type} eq 'ARRAY')
    {
        foreach my $ref (@{$index->{files}{$file}{$type}})
        {
            @{$index->{$type}{$ref}} = grep { $_->{file} ne $file } @{$index->{$type}{$ref}};
            delete $index->{$type}{$ref} unless (scalar @{$index->{$type}{$ref}});
        } ## end foreach my $ref (@{$index->...})

        @{$index->{files}{$file}{$type}} = ();
    } ## end if (ref $index->{files...})
    else
    {
        $index->{files}{$file}{$type} = [];
    }
} ## end sub cleanup_index

sub update_index
{
    my ($self, $index, $type, @references) = @_;

    foreach my $reference (@references)
    {
        my $info = $reference->location_info();

        if (ref $index->{$type}{$reference->name} eq 'ARRAY')
        {
            push @{$index->{$type}{$reference->name}}, $info;

        }
        else
        {
            $index->{$type}{$reference->name} = [$info];
        }
    } ## end foreach my $reference (@references...)
} ## end sub update_index

sub find_package_subroutine
{
    my ($self, $package, $subroutine) = @_;

    my @path = split '::', $package;
    my $package_path = File::Spec->join(@path) . '.pm';

    $self->index_files();
    my $index = $self->index();

    foreach my $file (keys %{$index->{files}})
    {
        next unless ($file =~ /\Q$package_path\E$/);
        return $self->find_subroutine($subroutine, $file);
    }

    return;
} ## end sub find_package_subroutine

sub find_subroutine
{
    my ($self, $subroutine, @files) = @_;

    $self->index_files(@files);
    my $index = $self->index;
    my $found = $index->{subs}{$subroutine};
    return [] unless (ref $found eq 'ARRAY');

    my @locations = @$found;

    if (scalar @files)
    {
        @locations = grep {
            my $location = $_;
            grep { $location->{file} eq $_ } @files
        } @locations;
    } ## end if (scalar @files)

    return [
        map {
            {
             uri   => URI::file->new($_->{file})->as_string,
             range => {
                       start => {
                                 line      => $_->{location}{line_number},
                                 character => $_->{location}{column_number}
                                },
                       end => {
                               line      => $_->{location}{line_number},
                               character => $_->{location}{column_number} + (length $subroutine) + ($_->{constant} ? (length '') : (length 'sub '))
                              }
                      },
             signature => $_->{signature}
            }
          } @locations
    ];
} ## end sub find_subroutine

sub find_package
{
    my ($self, $package, @files) = @_;

    $self->index_files(@files);
    my $index = $self->index;
    my $found = $index->{packages}{$package};
    return [] unless (ref $found eq 'ARRAY');

    my @locations = @$found;

    if (scalar @files)
    {
        @locations = grep {
            my $location = $_;
            grep { $location->{file} eq $_ } @files
        } @locations;
    } ## end if (scalar @files)

    return [
        map {
            {
             uri   => URI::file->new($_->{file})->as_string,
             range => {
                       start => {
                                 line      => $_->{location}{line_number},
                                 character => $_->{location}{column_number}
                                },
                       end => {
                               line      => $_->{location}{line_number},
                               character => ($_->{location}{column_number} + length $package)
                              }
                      }
            }
          } @locations
    ];
} ## end sub find_package

sub get_all_perl_files
{
    my ($self) = @_;

    return unless (length $self->{root});

    my @perl_files;

    File::Find::find(
        sub {
            return unless -f;
            return if -l;
            return if /\.t$/;
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
            push @perl_files, $File::Find::name
              if (length $first_line and $first_line =~ /^#!.*perl$/);
            close $code;
        },
        $self->{root}
                    );

    return \@perl_files;
} ## end sub get_all_perl_files

1;
