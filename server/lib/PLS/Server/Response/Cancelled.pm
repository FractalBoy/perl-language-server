package PLS::Server::Response::Cancelled;

use parent q(PLS::Server::Response);

sub new
{
    my ($class, %args) = @_;

    return
      bless {
             id    => $args{id},
             error => {code => -32800, message => 'Request cancelled.'}
            }, $class;
} ## end sub new

1;
