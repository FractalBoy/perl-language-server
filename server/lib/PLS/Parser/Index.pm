package PLS::Parser::Index;

use strict;
use warnings;
use feature 'state';

use File::Find;
use File::stat;
use File::Spec;
use URI::file;
use List::Util qw(any);
use Path::Tiny;
use PPR;
use Storable;
use Time::Piece;

=head1 NAME

PLS::Parser::Index

=head1 DESCRIPTION

This class caches and stores indexed data about the workspace.
It is used for quick searching of subroutines and packages by name.

=cut

sub new
{
    my ($class, @args) = @_;

    my %args = @args;

    my $self = bless {
                      root  => $args{root},
                      cache => {},
                     }, $class;

    $self->index_files();

    return $self;
} ## end sub new

sub index_files
{
    my ($self, @files) = @_;

    @files = @{$self->get_all_perl_files()} unless (scalar @files);

    my $current = 0;
    my $total   = scalar @files;

    foreach my $file (@files)
    {
        $current++;
        open my $fh, '<', $file or next;

        my $log_message = "Indexing $file";
        $log_message .= " ($current/$total)" if ($total > 1);
        $log_message .= '...';

        $self->log($log_message);

        my $text         = do { local $/; <$fh> };
        my $line_offsets = $self->get_line_offsets(\$text);
        my $packages     = $self->get_packages(\$text, $file, $line_offsets);
        my $subroutines  = $self->get_subroutines(\$text, $file, $line_offsets);

        foreach my $name (keys %{$packages})
        {
            push @{$self->{cache}{packages}{$name}},        @{$packages->{$name}};
            push @{$self->{cache}{files}{$file}{packages}}, $name;
        }

        foreach my $name (keys %{$subroutines})
        {
            push @{$self->{cache}{subs}{$name}},        @{$subroutines->{$name}};
            push @{$self->{cache}{files}{$file}{subs}}, $name;
        }

    } ## end foreach my $file (@files)

    return;
} ## end sub index_files

sub cleanup_index
{
    my ($self, $type, $file) = @_;

    my $index = $self->{cache};

    if (ref $index->{files}{$file}{$type} eq 'ARRAY')
    {
        foreach my $ref (@{$index->{files}{$file}{$type}})
        {
            @{$index->{$type}{$ref}} = grep { $_->{uri} ne $file } @{$index->{$type}{$ref}};
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
            $self->log("Cleaning up $file from index...");

            if (ref $index->{subs} eq 'HASH')
            {
                foreach my $sub (@{$index->{files}{$file}{subs}})
                {
                    next unless (ref $index->{subs}{$sub} eq 'ARRAY');
                    @{$index->{subs}{$sub}} = grep { $_->{uri} eq $file } @{$index->{subs}{$sub}};
                    delete $index->{subs}{$sub} unless (scalar @{$index->{subs}{$sub}});
                } ## end foreach my $sub (@{$index->...})
            } ## end if (ref $index->{subs}...)

            if (ref $index->{packages} eq 'HASH')
            {
                foreach my $package (@{$index->{files}{$file}{packages}})
                {
                    next unless (ref $index->{packages}{$package} eq 'ARRAY');
                    @{$index->{packages}{$package}} = grep { $_->{uri} eq $file } @{$index->{packages}{$package}};
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

        $self->log("Cleaning up $type references from index...") if ($refs_cleaned);
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

        push @{$packages{$name}},
          {
            uri   => URI::file->new($file)->as_string(),
            start => {
                      line      => $start_line,
                      character => $start
                     },
            end => {
                    line      => $end_line,
                    character => $end
                   }
          };
    } ## end while ($$text =~ /$rx/g)

    return \%packages;
} ## end sub get_packages

sub get_subroutines
{
    my ($class, $text, $file, $line_offsets) = @_;

    state $sub_rx   = qr/((?&PerlSubroutineDeclaration))$PPR::GRAMMAR/;
    state $block_rx = qr/((?&PerlOWS)(?&PerlBlock))$PPR::GRAMMAR/;
    state $sig_rx   = qr/(?<label>(?<params>(?&PerlVariableDeclaration))(?&PerlOWS)=(?&PerlOWS)\@_)$PPR::GRAMMAR/;
    state $var_rx   = qr/((?&PerlVariable))$PPR::GRAMMAR/;
    my %subroutines;

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

        if ($name =~ s/$block_rx//)
        {
            my $block = $1;

            if ($block =~ /$sig_rx/)
            {
                $signature = $+{label};
                my $parameters = $+{params};
                while ($parameters =~ /$var_rx/g)
                {
                    push @parameters, {label => $1};
                }
            } ## end if ($block =~ /$sig_rx/...)
        } ## end if ($name =~ s/$block_rx//...)

        $name =~ s/my|our|state|sub//g;
        $name =~ s/^\s+|\s+$//g;

        push @{$subroutines{$name}},
          {
            uri   => URI::file->new($file)->as_string(),
            start => {
                      line      => $start_line,
                      character => $start
                     },
            end => {
                    line      => $end_line,
                    character => $end
                   },
            signature => {label => $signature, parameters => \@parameters}
          };
    } ## end while ($$text =~ /$sub_rx/g...)

    return \%subroutines;
} ## end sub get_subroutines

1;
