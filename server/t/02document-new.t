#!perl

use Test2::V0;

use FindBin;
use File::Basename;
use File::Path;
use File::Spec;
use File::Temp;
use URI;

use PLS::Parser::Document;
use PLS::Server::State;

plan tests => 5;

my $index = PLS::Parser::Index->new(workspace_folders => [$FindBin::RealBin]);

subtest 'new with uri' => sub {
    plan tests => 4;

    my $uri = URI::file->new(File::Spec->catfile($FindBin::RealBin, $FindBin::RealScript));
    my $doc = PLS::Parser::Document->new(uri => $uri->as_string);

    is($doc,             check_isa('PLS::Parser::Document'), 'PLS document valid');
    is($doc->{document}, check_isa('PPI::Document'),         'PPI document valid');
    is($doc->{index},    check_isa('PLS::Parser::Index'),    'index valid');

    subtest 'new with line' => sub {
        plan tests => 5;

        $doc               = PLS::Parser::Document->new(uri => $uri->as_string, line => 5);
        $index->{subs}     = {};
        $index->{packages} = {};
        $index->{files}    = {};
        is($doc,             check_isa('PLS::Parser::Document'), 'PLS document valid');
        is($doc->{document}, check_isa('PPI::Document'),         'PPI document valid');
        is($doc->{index},    check_isa('PLS::Parser::Index'),    'index valid');
        is($doc->{one_line}, T(),                                'one line flag on');

        my $file  = $doc->{document}->serialize();
        my @lines = split /\n/, $file;
        is(\@lines, meta { prop size => 1 }, 'only one line in document');
    }; ## end 'new with line' => sub
}; ## end 'new with uri' => sub

subtest 'new with path' => sub {
    plan tests => 3;

    my $uri = URI::file->new(File::Spec->catfile($FindBin::RealBin, $FindBin::RealScript));
    $index->{subs}     = {};
    $index->{packages} = {};
    $index->{files}    = {};
    my $doc = PLS::Parser::Document->new(path => $uri->file);

    is($doc,             check_isa('PLS::Parser::Document'), 'PLS document valid');
    is($doc->{document}, check_isa('PPI::Document'),         'PPI document valid');
    is($doc->{index},    check_isa('PLS::Parser::Index'),    'index valid');
}; ## end 'new with path' => sub

subtest 'new without path or uri' => sub {
    plan tests => 1;

    my $doc = PLS::Parser::Document->new();
    is($doc, U(), 'no document returned without path or uri');
}; ## end 'new without path or uri' => sub

subtest 'new with bad path' => sub {
    plan tests => 1;

    my $temp = File::Temp->new(unlink => 0);
    close $temp;
    unlink $temp->filename;
    my $doc = PLS::Parser::Document->new(path => $temp->filename);
    is($doc, U(), 'no document returned with nonexistent path');
}; ## end 'new with bad path' => sub

subtest 'new with bad uri' => sub {
    plan tests => 1;

    my $temp = File::Temp->new(unlink => 0);
    close $temp;
    unlink $temp->filename;
    my $uri = URI::file->new($temp->filename);
    my $doc = PLS::Parser::Document->new(uri => $uri->as_string);
    is($doc, U(), 'no document returned with nonexistent uri');
}; ## end 'new with bad uri' => sub
