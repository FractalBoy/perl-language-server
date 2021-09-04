package JJ;

use strict;
use warnings;

use Data::Dumper;

our $VERSION = '0.1';

=head1 NAME

JJ

=head1 DESCRIPTION

Simple debugging helper that logs in BBEdits Logs directory.

=cut

sub jjlog {
    my ( $sender, $object ) = @_;
    my $log_file_path =
        "~/Library/Containers/com.barebones.bbedit/Data/Library/Logs/BBEdit/perl-PLS.log";
    open( FH, '>>', glob( $log_file_path ) ) or die $!;
    print FH $sender . ': ' . Dumper( $object );
    close FH;

    return;
}

1;
