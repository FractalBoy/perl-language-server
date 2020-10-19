package PLS::Server::Response::SignatureHelp;
use parent q(PLS::Server::Response);

use strict;
use warnings;

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});
    my $results = $document->go_to_definition(
                                              $request->{params}{position}{line},
                                              $request->{params}{position}{character} - 1    # we want the word before the open paren
                                             );
    use Data::Dumper;
    warn Dumper $results;

    my @signatures = map { $_->{signature} } @$results;

    my %self = (
                id     => $request->{id},
                result => scalar @signatures ? {signatures => \@signatures} : undef
               );

    return bless \%self, $class;
} ## end sub new

1;
