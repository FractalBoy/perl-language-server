package PLS::Server::Request::WorkDoneProgress;

use strict;
use warnings;

use parent 'PLS::Server::Request';

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
