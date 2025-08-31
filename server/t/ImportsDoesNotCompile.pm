package t::ImportsDoesNotCompile;    ## no critic (Capitalization RequireFilenameMatchesPackage)

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::RealBin/..";
}

use t::DoesNotCompile;

1;
