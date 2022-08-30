package PLS::Server::Response::RangeFormatting;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use IO::Async::Function;
use IO::Async::Loop;

use PLS::Parser::Document;
use PLS::Server::State;

=head1 NAME

PLS::Server::Response::RangeFormatting

=head1 DESCRIPTION

This is a message from the server to the client with a document range
after having been formatted.

=cut

# Set up formatting as a function because it can be slow
my $loop = IO::Async::Loop->new();
my $function = IO::Async::Function->new(
    code => sub {
        my ($self, $request, $text, $perltidyrc) = @_;

        my ($ok, $formatted) = PLS::Parser::Document->format_range(text => $text, range => $request->{params}{range}, formatting_options => $request->{params}{options}, perltidyrc => $perltidyrc);
        return $ok, $formatted;
    }
);
$loop->add($function);

sub new
{
    my ($class, $request) = @_;

    if (ref $request->{params}{options} eq 'HASH')
    {
        # these options aren't really valid for range formatting
        delete $request->{params}{options}{trimFinalNewlines};
        delete $request->{params}{options}{insertFinalNewline};
    } ## end if (ref $request->{params...})

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
