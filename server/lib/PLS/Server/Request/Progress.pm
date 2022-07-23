package PLS::Server::Request::Progress;

use strict;
use warnings;

use parent 'PLS::Server::Request';

=head1 NAME

PLS::Server::Request::Progress

=head1 DESCRIPTION

This is a generic notification, sent from server to client,
used to report any kind of progress.

=cut

sub new
{
    my ($class, %args) = @_;

    my $token = delete $args{token};

    my $self = {
                method       => '$/progress',
                params       => {token => $token, value => \%args},
                notification => 1
               };

    return bless $self, $class;
} ## end sub new

1;
