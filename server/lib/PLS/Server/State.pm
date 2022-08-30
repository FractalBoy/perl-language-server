package PLS::Server::State;

use strict;
use warnings;

our $INITIALIZED = 0;
our $ROOT_PATH;
our $CONFIG   = {perltidy => {}, perlcritic => {}};
our $SHUTDOWN = 0;
our $CLIENT_CAPABILITIES;

=head1 NAME

PLS::Server::State

=head1 DESCRIPTION

This module contains package variables containing server state.

=cut

1;
