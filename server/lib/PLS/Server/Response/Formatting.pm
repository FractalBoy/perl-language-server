package PLS::Server::Response::Formatting;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use IO::Async::Function;
use IO::Async::Loop;

use PLS::Parser::Document;
use PLS::Server::State;

=head1 NAME

PLS::Server::Response::Formatting

=head1 DESCRIPTION

This is a message from the server to the client with the current document
after having been formatted.

=cut

# Set up formatting as a function because it can be slow
my $loop = IO::Async::Loop->new();
my $function = IO::Async::Function->new(
    code => sub {
        my ($self, $request, $text, $perltidyrc) = @_;

        my ($ok, $formatted) = PLS::Parser::Document->format(text => $text, formatting_options => $request->{params}{options}, perltidyrc => $perltidyrc);
        return $ok, $formatted;
    }
);
$loop->add($function);

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}}, $class;
    my $text = PLS::Parser::Document->text_from_uri($request->{params}{textDocument}{uri});

    return $function->call(args => [$self, $request, $text, $PLS::Server::State::CONFIG->{perltidy}{perltidyrc}])->then(
        sub {
            my ($ok, $formatted) = @_;

            if ($ok)
            {
                $self->{result} = $formatted;
            }
            else
            {
                $self->{error} = $formatted;
            }

            return $self;
        }
    );
} ## end sub new

1;
