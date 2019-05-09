package Perl::LanguageServer::Request;

use strict;

use JSON;
use List::Util;

sub new {
    my ($class, @args) = @_;

    my %self = @args;

    my @required_args = ( 'headers', 'content' );
    die 'missing named argument to Request.pm' unless
        (   
            (List::Util::all { my $req = $_; List::Util::any { $_ eq $req } (keys %self) } @required_args) &&
            keys %self == @required_args
        );

    return bless \%self, $class;
}

1;