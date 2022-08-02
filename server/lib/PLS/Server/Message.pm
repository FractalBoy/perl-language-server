package PLS::Server::Message;

use strict;
use warnings;

use PLS::JSON;

=head1 NAME

PLS::Server::Message

=head1 DESCRIPTION

This class is the abstract base class for all messages sent between
server and client.

See L<PLS::Server::Request> and L<PLS::Server::Response>, which
inherit from this class.

=cut

sub serialize
{
    my ($self) = @_;

    my %content = (
                   jsonrpc => '2.0',
                   %{$self}
                  );

    my $json = encode_json \%content;
    return \$json;
} ## end sub serialize

1;
