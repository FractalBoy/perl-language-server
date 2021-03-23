package PLS::Server::Response::SignatureHelp;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri}, line => $request->{params}{position}{line});
    my $results  = $document->go_to_definition($request->{params}{position}{line}, $request->{params}{position}{character});

    my @signatures       = map { $_->{signature} } @$results;
    my $active_parameter = $document->get_list_index($request->{params}{position}{line}, $request->{params}{position}{character});

    my %self = (
                id     => $request->{id},
                result => scalar @signatures ? {signatures => \@signatures, activeParameter => $active_parameter} : undef
               );

    return bless \%self, $class;
} ## end sub new

1;
