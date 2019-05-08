package Perl::LanguageServer;

use strict;

use Data::Dumper;

use Perl::Request;

our $INITIALIZED = 0;
our $NEXT_REQUEST_ID = 0;

sub run {
    while (!eof(STDIN)) {
        my $request = Perl::Request->new(\*STDIN);

        if ($request->{content}{method} eq 'initialize') {
            next if $INITIALIZED;
            $INITIALIZED = 1;
            
            

            next;
        }

        if (!$INITIALIZED) {
            # send error code: -32002
        }
    }
}

sub next_request_id {
    return $NEXT_REQUEST_ID++;
}

1;