package PLS::Server::State;

use strict;

our $INITIALIZED = 0;
our @CANCELED;
our $ROOT_PATH;
our $INDEX_LAST_MTIME;
our $INDEX;
our $FILES = {};

1;
