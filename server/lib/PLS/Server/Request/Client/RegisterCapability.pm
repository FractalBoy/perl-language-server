package PLS::Server::Request::Client::RegisterCapability;

use parent 'PLS::Server::Request';

sub new
{
    my ($class, $registrations) = @_;

    my %self = (
                method => 'client/registerCapability',
                params => {
                           registrations => $registrations
                          }
               );

    return bless \%self, $class;
} ## end sub new

1;
