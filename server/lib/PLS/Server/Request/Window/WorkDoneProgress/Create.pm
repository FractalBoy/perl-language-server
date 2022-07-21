package PLS::Server::Request::Window::WorkDoneProgress::Create;

use strict;
use warnings;

use parent 'PLS::Server::Request';

sub new
{
    my ($class) = @_;

    my @hex_chars = ('0' .. '9', 'A' .. 'F');
    my $token     = join '', map { $hex_chars[rand @hex_chars] } 1 .. 8;

    return bless {method => 'window/workDoneProgress/create', params => {token => $token}}, $class;
} ## end sub new

1;
