package PLS::Server::Response::Hover;

use strict;
use warnings;

use parent q(PLS::Server::Response);
use feature 'state';

use PLS::Parser::Document;
use PLS::Server::State;

=head1 NAME

PLS::Server::Response::Hover

=head1 DESCRIPTION

This is a message from the server to the client with
documentation for the location the mouse is currently hovering.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = bless {
                      id     => $request->{id},
                      result => undef
                     }, $class;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri}, line => $request->{params}{position}{line});
    return $self if (ref $document ne 'PLS::Parser::Document');

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
                return $document->find_pod($uri, 1, $character);
            }
        );

        IO::Async::Loop->new->add($function);
    } ## end if (not $function)

    return
      $function->call(
                      args => [
                               $request->{params}{textDocument}{uri},
                               $request->{params}{position}{line},
                               $request->{params}{position}{character},
                               $PLS::Server::State::CONFIG,
                               {$request->{params}{textDocument}{uri} => $PLS::Parser::Document::FILES{$request->{params}{textDocument}{uri}}},
                               {$request->{params}{textDocument}{uri} => $PLS::Parser::Document::VERSIONS{$request->{params}{textDocument}{uri}}},
                              ]
      )->then(
        sub {
            my ($ok, $pod) = @_;
            return $self unless $ok;
            $self->{result} = {
                               contents => {kind => 'markdown', value => ${$pod->{markdown}}},
                               range    => $pod->{element}->range()
                              };
            return $self;
        }
      );
} ## end sub new

1;
