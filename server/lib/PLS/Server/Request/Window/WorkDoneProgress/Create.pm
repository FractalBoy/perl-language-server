package PLS::Server::Request::Window::WorkDoneProgress::Create;

use strict;
use warnings;

use parent 'PLS::Server::Request';

=head1 NAME

PLS::Server::Request::Window::WorkDoneProgress::Create

=head1 DESCRIPTION

This is a request from the server to the client to ask the client
to create a work done progress.

=cut

sub new
{
    my ($class) = @_;

    my @hex_chars = ('0' .. '9', 'A' .. 'F');
    my $token     = join '', map { $hex_chars[rand @hex_chars] } 1 .. 8;

    return bless {method => 'window/workDoneProgress/create', params => {token => $token}}, $class;
} ## end sub new

1;
