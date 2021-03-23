package PLS::Parser::Index;

use strict;
use warnings;
use feature 'state';

use Coro;
use Coro::AnyEvent;
use File::Find;
use File::Path;
use File::stat;
use File::Spec;
use FindBin;
use List::Util qw(all any);
use Path::Tiny;
use Time::Piece;
use Storable;

use Trie;

use constant {INDEX_LOCATION => File::Spec->catfile('.pls_cache', 'index')};

my $indexing_semaphore = Coro::Semaphore->new();

sub new
{
    my ($class, @args) = @_;

    my %args = @args;

    my %self = (
                root                     => $args{root},
                location                 => File::Spec->catfile($args{root}, INDEX_LOCATION),
                cache                    => {},
                subs_trie                => Trie->new(),
                packages_trie            => Trie->new(),
                last_mtime               => 0,
                retrieve_index_semaphore => Coro::Semaphore->new()
               );

    return bless \%self, $class;
} ## end sub new

sub load_trie
{
    my ($self) = @_;

    my $index = $self->index();

    foreach my $sub (keys %{$index->{subs}})
    {
        my $count = scalar @{$index->{subs}{$sub}};
        $self->{subs_trie}->insert($sub, 1);
    }

    foreach my $package (keys %{$index->{packages}})
    {
        my $count = scalar @{$index->{packages}{$package}};
        $self->{packages_trie}->insert($package, 1);
    }
} ## end sub load_trie

sub index_files
{
    my ($self, @files) = @_;

    async
    {
        my ($self, @files) = @_;

        my $lock  = $self->lock();
        my $index = $self->index();

        unless (scalar @files)
        {
            @files = @{$self->get_all_perl_files()};
            $self->_cleanup_old_files($index);
            @files = grep { not exists $index->{files}{$_}{last_mtime} or not length $index->{files}{$_}{last_mtime} and $index->{files}{$_}{last_mtime} < stat($_)->mtime } @files;
        } ## end unless (scalar @files)

        my $total   = scalar @files;
        my $current = 0;

        foreach my $file (@files)
        {
            $current++;

            open my $fh, '<', $file or next;
            my $text     = do { local $/; <$fh> };
            my $document = PLS::Parser::Document->new(path => $file, text => \$text);
            next unless (ref $document eq 'PLS::Parser::Document');

            Coro::AnyEvent::sleep 0.01;

            my $log_message = "Indexing $file";
            $log_message .= " ($current/$total)" if (scalar @files > 1);
            $log_message .= '...';

            $self->log($log_message);

            $self->update_subroutines($index, $document);
            Coro::AnyEvent::sleep 0.01;
            $self->update_packages($index, $document);
            Coro::AnyEvent::sleep 0.01;
        } ## end foreach my $file (@files)

        $self->save($index);
    } ## end async
    $self, @files;
} ## end sub index_files

sub lock
{
    return $indexing_semaphore->guard();
}

sub save
{
    my ($self, $index) = @_;

    my (undef, $parent_dir) = File::Spec->splitpath($self->{location});
    File::Path::make_path($parent_dir);

    Storable::nstore($index, $self->{location});
    $self->{cache}      = $index;
    $self->{last_mtime} = (stat $self->{location})->mtime;
} ## end sub save

sub index
{
    my ($self) = @_;

    return {} unless -f $self->{location};

    # Don't have two coroutines retrieving the index at the same time
    my $guard = $self->{retrieve_index_semaphore}->guard();
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
    $self->update_index($index, 'subs', $document->{path}, @$subroutines, @$constants);
} ## end sub update_subroutines

sub update_packages
{
    my ($self, $index, $document) = @_;

    my $packages = $document->get_packages();

    $self->cleanup_index($index, 'packages', $document->{path});
    return unless (ref $packages eq 'ARRAY');
    $self->update_index($index, 'packages', $document->{path}, @$packages);
} ## end sub update_packages

sub cleanup_index
{
    my ($self, $index, $type, $file) = @_;

    my $trie = $self->{"${type}_trie"};

    if (ref $index->{files}{$file}{$type} eq 'ARRAY')
    {
        foreach my $ref (@{$index->{files}{$file}{$type}})
        {
            @{$index->{$type}{$ref}} = grep { $_->{file} ne $file } @{$index->{$type}{$ref}};
            delete $index->{$type}{$ref} unless (scalar @{$index->{$type}{$ref}});

            my $node = $trie->find_node($ref);
            if (ref $node eq 'Node')
            {
                $node->{value}--;
                $trie->delete($ref) unless ($node->{value});
            }
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
    my ($self, $index, $type, $file, @references) = @_;

    my $trie = $self->{"${type}_trie"};

    foreach my $reference (@references)
    {
        my $info = $reference->location_info();

        if (ref $index->{$type}{$reference->name} eq 'ARRAY')
        {
            push @{$index->{$type}{$reference->name}}, $info;

            my $node = $trie->find_node($reference->name);

            if (ref $node eq 'Node')
            {
                $node->{value}++;
            }
            else
            {
                $trie->insert($reference->name, 1);
            }
        } ## end if (ref $index->{$type...})
        else
        {
            $index->{$type}{$reference->name} = [$info];
            $trie->insert($reference->name, 1);
        }

        push @{$index->{files}{$file}{$type}}, $reference->name;
    } ## end foreach my $reference (@references...)

    $index->{files}{$file}{last_mtime} = stat($file)->mtime;
} ## end sub update_index

sub cleanup_old_files
{
    my ($self) = @_;

    async
    {
        my $lock  = $self->lock();
        my $index = $self->index();
        $self->_cleanup_old_files($index);
        $self->save($index);
    } ## end async
} ## end sub cleanup_old_files

sub _cleanup_old_files
{
    my ($self, $index) = @_;

    if (ref $index->{files} eq 'HASH')
    {
        foreach my $file (keys %{$index->{files}})
        {
            next if -f $file;
            $self->log("Cleaning up $file from index...");

            if (ref $index->{subs} eq 'HASH')
            {
                foreach my $sub (@{$index->{files}{$file}{subs}})
                {
                    next unless (ref $index->{subs}{$sub} eq 'ARRAY');
                    @{$index->{subs}{$sub}} = grep { $_->{file} eq $file } @{$index->{subs}{$sub}};
                    delete $index->{subs}{$sub} unless (scalar @{$index->{subs}{$sub}});
                } ## end foreach my $sub (@{$index->...})
            } ## end if (ref $index->{subs}...)

            if (ref $index->{packages} eq 'HASH')
            {
                foreach my $package (@{$index->{files}{$file}{packages}})
                {
                    next unless (ref $index->{packages}{$package} eq 'ARRAY');
                    @{$index->{packages}{$package}} = grep { $_->{file} eq $file } @{$index->{packages}{$package}};
                    delete $index->{packages}{$package} unless (scalar @{$index->{packages}{$package}});
                } ## end foreach my $package (@{$index...})
            } ## end if (ref $index->{packages...})

            delete $index->{files}{$file};
        } ## end foreach my $file (keys %{$index...})
    } ## end if (ref $index->{files...})
} ## end sub _cleanup_old_files

sub find_package_subroutine
{
    my ($self, $package, $subroutine) = @_;

    my $index     = $self->index();
    my $locations = $index->{packages}{$package};

    if (ref $locations ne 'ARRAY')
    {
        my $external = PLS::Parser::Document->find_external_subroutine($package, $subroutine);
        return [$external] if (ref $external eq 'HASH');
        return [];
    } ## end if (ref $locations ne ...)

    foreach my $file (@$locations)
    {
        return $self->find_subroutine($subroutine, $file->{file});
    }

    return;
} ## end sub find_package_subroutine

sub find_subroutine
{
    my ($self, $subroutine, @files) = @_;

    my $index = $self->index;
    my $found = $index->{subs}{$subroutine};
    return [] unless (ref $found eq 'ARRAY');

    my @locations = @$found;

    if (scalar @files)
    {
        @locations = grep {
            my $location = $_;
            scalar grep { $location->{file} eq $_ } @files;
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
                               character => $_->{location}{column_number} + (length $subroutine) + ($_->{constant} ? 0 : (length 'sub '))
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

    my $index = $self->index;
    my $found = $index->{packages}{$package};

    if (ref $found ne 'ARRAY')
    {
        my $external = PLS::Parser::Document->find_external_package($package);
        return [$external] if (ref $external eq 'HASH');
        return [];
    } ## end if (ref $found ne 'ARRAY'...)

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
                               character => ($_->{location}{column_number} + length($package) + length('package ') + length(';'))
                              }
                      }
            }
          } @locations
    ];
} ## end sub find_package

sub get_ignored_files
{
    my ($self) = @_;

    my @ignore_files;
    my $plsignore = File::Spec->catfile($self->{root}, '.plsignore');

    return [] unless (-f $plsignore and -r $plsignore);

    my $mtime = stat($plsignore)->mtime;
    return $self->{ignored_files} if (length $self->{ignore_file_last_mtime} and $self->{ignore_file_last_mtime} >= $mtime);

    if (open my $fh, '<', File::Spec->catfile($self->{root}, '.plsignore'))
    {
        while (my $line = <$fh>)
        {
            chomp $line;
            push @ignore_files, glob File::Spec->catfile($self->{root}, $line);
        }
    } ## end if (open my $fh, '<', ...)

    @ignore_files                   = map { path($_)->realpath } @ignore_files;
    $self->{ignored_files}          = \@ignore_files;
    $self->{ignore_file_last_mtime} = $mtime;

    return $self->{ignored_files};
} ## end sub get_ignored_files

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
    my ($self) = @_;

    return unless (length $self->{root});

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
        $self->{root}
                    );

    return \@perl_files;
} ## end sub get_all_perl_files

sub is_perl_file
{
    my ($class, $file) = @_;

    return if -l $file;
    return unless -f $file;
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
} ## end sub log

1;
