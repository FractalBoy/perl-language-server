package PLS::Server::Response::Location;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use PLS::Parser::Document;

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

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});
    return $self if (ref $document ne 'PLS::Parser::Document');

    my $results = $document->go_to_definition(@{$request->{params}{position}}{qw(line character)});

    if (ref $results eq 'ARRAY')
    {
        foreach my $result (@$results)
        {
            delete @{$result}{qw(package signature kind)};
        }
    } ## end if (ref $results eq 'ARRAY'...)

    $self->{result} = $results;
    return $self;
} ## end sub new

1;
