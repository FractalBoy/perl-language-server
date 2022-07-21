package PLS::Parser::Index;

use strict;
use warnings;

use feature 'state';

use File::Find;
use File::Spec;
use File::stat;
use IO::Async::Function;
use IO::Async::Loop;
use List::Util qw(any);
use POSIX;
use PPR;
use Path::Tiny;
use Storable;
use Time::Piece;
use URI::file;

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
                   workspace_folders   => $args{workspace_folders},
                   subs                => {},
                   packages            => {},
                   files               => {},
                   ignored_files       => {},
                   ignore_files_mtimes => {}
                  }, $class;

    return $self;
} ## end sub new

sub workspace_folders
{
    my ($self) = @_;

    return $self->{workspace_folders};
}

sub subs
{
    my ($self) = @_;

    return $self->{subs};
}

sub packages
{
    my ($self) = @_;

    return $self->{packages};
}

sub files
{
    my ($self) = @_;

    return $self->{files};
}

sub _index_file
{
    my ($uri) = @_;

    require PLS::Parser::Document;
    my $text         = PLS::Parser::Document->text_from_uri($uri);
    my $line_offsets = PLS::Parser::Index->get_line_offsets($text);
    my $packages     = PLS::Parser::Index->get_packages($text, $uri, $line_offsets);
    my $subroutines  = PLS::Parser::Index->get_subroutines($text, $uri, $line_offsets);

    return $packages, $subroutines;
} ## end sub _index_file

sub index_files
{
    my ($self, @uris) = @_;

    state $function;

    if (ref $function ne 'IO::Async::Function')
    {
        $function = IO::Async::Function->new(code => \&_index_file);
        IO::Async::Loop->new->add($function);
    }

    my $get_files_future;

    if (scalar @uris)
    {
        $get_files_future = Future->done(\@uris);
    }
    else
    {
        $get_files_future = $self->get_all_perl_files_async();
    }

    return $get_files_future->then(
        sub {
            my ($uris) = @_;

            my @futures;

            foreach my $uri (@{$uris})
            {
                push @futures, $function->call(args => [$uri])->then(
                    sub {
                        my ($packages, $subs) = @_;

                        my $file = URI->new($uri)->file;
                        return if $self->is_ignored($file);

                        $file = readlink $file if (-l $file);
                        return                 if $self->is_ignored($file);

                        $self->cleanup_file($file);

                        foreach my $ref (keys %{$packages})
                        {
                            push @{$self->packages->{$ref}},         @{$packages->{$ref}};
                            push @{$self->files->{$file}{packages}}, $ref;
                        }

                        foreach my $ref (keys %{$subs})
                        {
                            push @{$self->subs->{$ref}},         @{$subs->{$ref}};
                            push @{$self->files->{$file}{subs}}, $ref;
                        }

                        return Future->done($file);
                    }
                );
            } ## end foreach my $uri (@{$uris})

            return Future->done(@futures);
        }
    )->retain();
} ## end sub index_files

sub get_all_perl_files_async
{
    my ($self, @folders) = @_;

    @folders = @{$self->workspace_folders} unless (scalar @folders);
    return Future->done([])                unless (scalar @folders);

    state $function;

    if (ref $function ne 'IO::Async::Function')
    {
        $function = IO::Async::Function->new(code => \&get_all_perl_files);

        IO::Async::Loop->new->add($function);
    } ## end if (ref $function ne 'IO::Async::Function'...)

    return $function->call(args => [$self, @folders]);
} ## end sub get_all_perl_files_async

sub deindex_workspace
{
    my ($self, $path) = @_;

    @{$self->workspace_folders} = grep { $_ ne $path } @{$self->workspace_folders};

    foreach my $file (keys %{$self->files})
    {
        next unless path($path)->subsumes($file);

        $self->cleanup_file($file);
    } ## end foreach my $file (keys %{$self...})

    return;
} ## end sub deindex_workspace

sub index_workspace
{
    my ($self, $path) = @_;

    push @{$self->workspace_folders}, $path;

    $self->get_all_perl_files_async($path)->then(
        sub {
            my ($workspace_uris) = @_;

            return $self->index_files(@{$workspace_uris});
        }
    )->then(sub { Future->wait_all(@_) })->retain();

    return;
} ## end sub index_workspace

sub _cleanup_index
{
    my ($self, $type, $file) = @_;

    if (ref $self->files->{$file}{$type} eq 'ARRAY')
    {
        foreach my $ref (@{$self->files->{$file}{$type}})
        {
            @{$self->$type->{$ref}} = grep { $_->{uri} ne URI::file->new($file)->as_string() } @{$self->$type->{$ref}};
            delete $self->$type->{$ref} unless (scalar @{$self->$type->{$ref}});
        }

        @{$self->files->{$file}{$type}} = ();
    } ## end if (ref $self->files->...)
    else
    {
        $self->files->{$file}{$type} = [];
    }

    return;
} ## end sub _cleanup_index

sub cleanup_file
{
    my ($self, $file) = @_;

    foreach my $type (qw(subs packages))
    {
        $self->_cleanup_index($type, $file);
    }

    delete $self->files->{$file};

    return;
} ## end sub cleanup_file

sub find_package_subroutine
{
    my ($self, $package, $subroutine) = @_;

    my $locations = $self->packages->{$package};

    if (ref $locations ne 'ARRAY')
    {
        require PLS::Parser::Document;
        my $external = PLS::Parser::Document->find_external_subroutine($package, $subroutine);
        return [$external] if (ref $external eq 'HASH');
        return [];
    } ## end if (ref $locations ne ...)

    my @subroutines;

    foreach my $file (@{$locations})
    {
        push @subroutines, @{$self->find_subroutine($subroutine, $file->{uri})};
    }

    return \@subroutines;
} ## end sub find_package_subroutine

sub find_subroutine
{
    my ($self, $subroutine, @uris) = @_;

    my $found = $self->subs->{$subroutine};
    return [] unless (ref $found eq 'ARRAY');

    $found = Storable::dclone($found);
    my %uris = map { $_ => 1 } @uris;
    @{$found} = grep { $uris{$_->{uri}} } @{$found} if (scalar @uris);

    return $found;
} ## end sub find_subroutine

sub find_package
{
    my ($self, $package) = @_;

    my $found = $self->packages->{$package};

    if (ref $found ne 'ARRAY')
    {
        require PLS::Parser::Document;
        my $external = PLS::Parser::Document->find_external_package($package);
        return [$external] if (ref $external eq 'HASH');
        return [];
    } ## end if (ref $found ne 'ARRAY'...)

    return Storable::dclone($found);
} ## end sub find_package

sub get_ignored_files
{
    my ($self) = @_;

    foreach my $workspace_folder (@{$self->workspace_folders})
    {
        my $plsignore = File::Spec->catfile($workspace_folder, '.plsignore');
        next if (not -f $plsignore or not -r $plsignore);

        my $mtime = stat($plsignore)->mtime;
        next if (length $self->{ignore_files_mtimes}{$plsignore} and $self->{ignore_file_mtimes}{$plsignore} >= $mtime);

        open my $fh, '<', $plsignore or next;

        $self->{ignored_files}{$plsignore}      = [];
        $self->{ignore_file_mtimes}{$plsignore} = $mtime;

        while (my $line = <$fh>)
        {
            chomp $line;
            push @{$self->{ignored_files}{$plsignore}}, glob File::Spec->catfile($workspace_folder, $line);
        }

        @{$self->{ignored_files}{$plsignore}} = map { path($_)->realpath } @{$self->{ignored_files}{$plsignore}};
    } ## end foreach my $workspace_folder...

    return [map { @{$self->{ignored_files}{$_}} } keys %{$self->{ignored_files}}];
} ## end sub get_ignored_files

sub get_all_subroutines
{
    my ($self) = @_;

    return [] if (ref $self->subs ne 'HASH');
    return [keys %{$self->subs}];
} ## end sub get_all_subroutines

sub get_all_packages
{
    my ($self) = @_;

    return [] if (ref $self->packages ne 'HASH');
    return [keys %{$self->packages}];
} ## end sub get_all_packages

sub is_ignored
{
    my ($self, $file) = @_;

    my @ignore_files = @{$self->get_ignored_files()};
    return unless (scalar @ignore_files);

    my $real_path = path($file)->realpath;

    return 1 if any { $_ eq $real_path } @ignore_files;
    return 1 if any { $_->subsumes($real_path) } @ignore_files;

    return;
} ## end sub is_ignored

sub get_all_perl_files
{
    my ($self, @folders) = @_;

    @folders = @{$self->workspace_folders} unless (scalar @folders);
    return []                              unless (scalar @folders);

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

    return [map { URI::file->new($_)->as_string } @perl_files];
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
    my ($class, $text, $uri, $line_offsets) = @_;

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
        $name =~ s/;\s*$//g;
        $name =~ s/^\s+|\s+$//g;

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
    my ($class, $text, $uri, $line_offsets) = @_;

    # Stolen mostly from PPR definition for PerlSubroutineDeclaration
    state $sub_rx = qr/
        (?<full>
        (?<declaration>(?>
            (?: (?> my | our | state ) \b      (?>(?&PerlOWS)) )?+
            sub \b                             (?>(?&PerlOWS))
            (?<name>(?>(?&PerlOldQualifiedIdentifier)))    (?&PerlOWS)
        |
            (?<name>AUTOLOAD)                              (?&PerlOWS)
        |
            (?<name>DESTROY)                               (?&PerlOWS)
        ))
        (?:
            # Perl pre 5.028
            (?:
                (?>
                    (?<params>(?<label>(?&PerlParenthesesList)))    # Parameter list
                |
                    \( [^)]*+ \)               # Prototype (
                )
                (?&PerlOWS)
            )?+
            (?: (?>(?&PerlAttributes))  (?&PerlOWS) )?+
        |
            # Perl post 5.028
            (?: (?>(?&PerlAttributes))       (?&PerlOWS) )?+
            (?<params>(?<label>(?: (?>(?&PerlParenthesesList))  (?&PerlOWS) )?+))    # Parameter list
        )
        (?> ; | \{
            (?&PerlOWS)
			(?<label>(?<params>(?&PerlVariableDeclaration))(?&PerlOWS)=(?&PerlOWS)\@_;?)?
            (?&PerlOWS)
			(?>(?&PerlStatementSequence))
		\} )
        )
        $PPR::GRAMMAR/x;

    state $var_rx = qr/((?&PerlVariable)|undef)$PPR::GRAMMAR/;

    my %subroutines;

    while ($$text =~ /$sub_rx/g)
    {
        my $end   = pos($$text);
        my $start = $end - length $+{full};
        $end = $start + length $+{declaration};

        my $start_line = $class->get_line_by_offset($line_offsets, $start);
        $start -= $line_offsets->[$start_line];
        my $end_line = $class->get_line_by_offset($line_offsets, $end);
        $end -= $line_offsets->[$end_line];

        my $signature = $+{label};
        my @parameters;

        if (length $+{params})
        {
            my $parameters = $+{params};
            while ($parameters =~ /$var_rx/g)
            {
                push @parameters, {label => $1};
            }
        } ## end if (length $+{params})

        my $name = $+{name};

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
