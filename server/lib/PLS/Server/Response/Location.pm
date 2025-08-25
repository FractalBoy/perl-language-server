package PLS::Server::Response::Location;

use strict;
use warnings;

use parent q(PLS::Server::Response);
use feature 'state';

use PLS::Parser::Document;
use PLS::Server::State;

=head1 NAME

PLS::Server::Response::Location

=head1 DESCRIPTION

This is a message from the server to the client providing a location.
This is typically used to provide the location of the definition of a symbol.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = {
                id     => $request->{id},
                result => undef
               };

    bless $self, $class;

    my ($line, $character) = @{$request->{params}{position}}{qw(line character)};

    state $function;

    if (not $function)
    {
        $function = IO::Async::Function->new(
            code => sub {
                my ($uri, $line, $character, $config, $files, $versions) = @_;

                local $PLS::Server::State::CONFIG      = $config;
                local %PLS::Parser::Document::FILES    = %{$files};
                local %PLS::Parser::Document::VERSIONS = %{$versions};

                my $document = PLS::Parser::Document->new(uri => $uri, line => $line);
                return unless (ref $document eq 'PLS::Parser::Document');

                my $results = $document->go_to_definition($line, $character);

                # If there are no results, for a variable, we need to fall back to checking the entire document.
                if (ref $results ne 'ARRAY' or not scalar @{$results})
                {
                    my @matches = $document->find_elements_at_location($line, $character);

                    if (List::Util::any { $_->variable_name() } @matches)
                    {
                        $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});
                        return $self if (ref $document ne 'PLS::Parser::Document');
                        $results = $document->go_to_definition($line, $character);
                    } ## end if (List::Util::any { ...})
                } ## end if (ref $results ne 'ARRAY'...)

                return $results;
            }
        );
        IO::Async::Loop->new->add($function);
    } ## end if (not $function)

    return
      $function->call(
                      args => [
                               $request->{params}{textDocument}{uri},
                               $line, $character, $PLS::Server::State::CONFIG,
                               {$request->{params}{textDocument}{uri} => $PLS::Parser::Document::FILES{$request->{params}{textDocument}{uri}}},
                               {$request->{params}{textDocument}{uri} => $PLS::Parser::Document::VERSIONS{$request->{params}{textDocument}{uri}}},
                              ]
      )->then(
        sub {
            my ($results) = @_;

            if (ref $results eq 'ARRAY')
            {
                foreach my $result (@{$results})
                {
                    delete @{$result}{qw(package signature kind)};
                }
            } ## end if (ref $results eq 'ARRAY'...)

            $self->{result} = $results;
            return $self;
        }
      );
} ## end sub new

1;
