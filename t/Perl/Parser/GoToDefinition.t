use Perl::Parser::GoToDefinition;

use Test::More;

=pod

Test ideas:

declare %hash, check that $hash{subscript}, \%hash works
declare @array, check that $array[index], \@array works
declare $hash_ref, check that $hash_ref->{subscript}, $$hash_ref{subscript}
declare $blessed_hash_ref, check that $blessed_hash_ref->method works
declare $blessed_array_ref, check that $blessed_array_ref->method works (should be the same as previous)
declare sub sub_name {}, check that sub_name, sub_name(), &sub_name, \&sub_name works

=cut