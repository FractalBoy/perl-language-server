package PLS::JSON;

use strict;
use warnings;

use Exporter qw(import);

our $package;

BEGIN
{
    if ($INC{'Cpanel/JSON/XS.pm'} or eval { require Cpanel::JSON::XS; 1 })
    {
        $package = 'Cpanel::JSON::XS';
    }
    elsif (($INC{'JSON/XS.pm'} or eval { require JSON::XS; 1 }) and eval { JSON::XS->VERSION(3.0); 1 })
    {
        $package = 'JSON::XS';
    }
    else
    {
        require JSON::PP;
        $package = 'JSON::PP';
    }

    $package->import(qw(encode_json decode_json));

    *PLS::JSON::true  = $package->can('true');
    *PLS::JSON::false = $package->can('false');
} ## end BEGIN

our @EXPORT = qw(encode_json decode_json);

sub new
{
    return $package->new();
}

1;
