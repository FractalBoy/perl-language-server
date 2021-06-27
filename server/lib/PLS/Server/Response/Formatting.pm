package PLS::Server::Response::Formatting;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use PLS::Parser::Document;

=head1 NAME

PLS::Server::Response::Formatting

=head1 DESCRIPTION

This is a message from the server to the client with the current document
after having been formatted.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}}, $class;
    my ($ok, $formatted) = PLS::Parser::Document->format(uri => $request->{params}{textDocument}{uri}, formatting_options => $request->{params}{options});

    if ($ok)
    {
        $self->{result} = $formatted;
    }
    else
    {
        $self->{error} = $formatted;
    }

    return $self;
} ## end sub new

1;
