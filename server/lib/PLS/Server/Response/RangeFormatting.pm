package PLS::Server::Response::RangeFormatting;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use PLS::Parser::Document;

=head1 NAME

PLS::Server::Response::RangeFormatting

=head1 DESCRIPTION

This is a message from the server to the client with a document range
after having been formatted.

=cut

sub new
{
    my ($class, $request) = @_;

    if (ref $request->{params}{options} eq 'HASH')
    {
        # these options aren't really valid for range formatting
        delete $request->{params}{options}{trimFinalNewlines};
        delete $request->{params}{options}{insertFinalNewline};
    } ## end if (ref $request->{params...})

    my ($ok, $formatted) = PLS::Parser::Document->format_range(uri => $request->{params}{textDocument}{uri}, range => $request->{params}{range}, formatting_options => $request->{params}{options});

    my %self = (id => $request->{id}, result => undef);

    if ($ok)
    {
        $self{result} = $formatted;
    }
    else
    {
        delete $self{result};
        $self{error} = $formatted;
    }

    return bless \%self, $class;
} ## end sub new

1;
