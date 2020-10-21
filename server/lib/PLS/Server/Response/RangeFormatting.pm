package PLS::Server::Response::RangeFormatting;
use parent q(PLS::Server::Response);

use strict;

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});
    my ($ok, $formatted) = $document->format_range($request->{params}{textDocument}{range});

    my %self = (id => $request->{id});

    if ($ok)
    {
        $self{result} = $formatted;
    }
    else
    {
        $self{error} = $formatted;
    }

    return bless \%self, $class;
} ## end sub new

1;
