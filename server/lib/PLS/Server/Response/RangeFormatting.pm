package PLS::Server::Response::RangeFormatting;
use parent q(PLS::Server::Response);

use strict;

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});

    if (ref $request->{params}{options} eq 'HASH')
    {
        # these options aren't really valid for range formatting
        delete $request->{params}{options}{trimFinalNewlines};
        delete $request->{params}{options}{insertFinalNewline};
    }

    my ($ok, $formatted) = $document->format_range(range => $request->{params}{range}, formatting_options => $request->{params}{options});

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
