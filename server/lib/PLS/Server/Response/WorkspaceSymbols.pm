package PLS::Server::Response::WorkspaceSymbols;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my $query = $request->{params}{query};

    my $index = PLS::Parser::Document->get_index()->index();
    my @symbols;

    foreach my $name (keys %{$index->{subs}})
    {
        next if ($name !~ /\Q$query\E/i);

        my $refs = $index->{subs}{$name};

        foreach my $sub (@{$refs})
        {
            my $line_end = $sub->{location}{column_number} + (length $name);
            $line_end += length 'sub ' unless ($sub->{constant});

            push @symbols,
              {
                name     => $name,
                kind     => 12,
                location => {
                             uri   => URI::file->new($sub->{file})->as_string(),
                             range => {
                                       start => {line => $sub->{location}{line_number}, character => $sub->{location}{column_number}},
                                       end   => {line => $sub->{location}{line_number}, character => $line_end}
                                      }
                            }
              };
        } ## end foreach my $sub (@{$refs})
    } ## end foreach my $name (keys %{$index...})

    foreach my $name (keys %{$index->{packages}})
    {
        next if ($name !~ /\Q$query\E/i);

        my $refs = $index->{packages}{$name};

        foreach my $package (@{$refs})
        {
            my $line_end = $package->{location}{column_number} + (length $name);
            $line_end += length 'package ';

            push @symbols,
              {
                name     => $name,
                kind     => 4,
                location => {
                             uri   => URI::file->new($package->{file})->as_string(),
                             range => {
                                       start => {line => $package->{location}{line_number}, character => $package->{location}{column_number}},
                                       end   => {line => $package->{location}{line_number}, character => $line_end}
                                      }
                            }
              };
        } ## end foreach my $package (@{$refs...})
    } ## end foreach my $name (keys %{$index...})

    return
      bless {
             id     => $request->{id},
             result => \@symbols
            }, $class;
} ## end sub new

1;
