#!perl

use strict;
use warnings;

use Test::More tests => 5;
use FindBin;
use File::Basename;
use File::Path;
use File::Spec;
use File::Temp;
use URI;

use PLS::Parser::Document;
use PLS::Server::State;

my $index = PLS::Parser::Index->new(workspace_folders => [$FindBin::RealBin]);

subtest 'new with uri' => sub {
    plan tests => 4;

    my $uri = URI::file->new(File::Spec->catfile($FindBin::RealBin, $FindBin::RealScript));
    my $doc = PLS::Parser::Document->new(uri => $uri->as_string);

    isa_ok($doc,             'PLS::Parser::Document');
    isa_ok($doc->{document}, 'PPI::Document');
    isa_ok($doc->{index},    'PLS::Parser::Index');

    subtest 'new with line' => sub {
        plan tests => 5;

        $doc               = PLS::Parser::Document->new(uri => $uri->as_string, line => 5);
        $index->{subs}     = {};
        $index->{packages} = {};
        $index->{files}    = {};
        isa_ok($doc,             'PLS::Parser::Document');
        isa_ok($doc->{document}, 'PPI::Document');
        isa_ok($doc->{index},    'PLS::Parser::Index');
        ok($doc->{one_line}, 'one line flag on');

        my $file  = $doc->{document}->serialize();
        my @lines = split /\n/, $file;
        cmp_ok(scalar @lines, '==', 1, 'only one line in document');
    };
};

subtest 'new with path' => sub {
    plan tests => 3;

    my $uri = URI::file->new(File::Spec->catfile($FindBin::RealBin, $FindBin::RealScript));
    $index->{subs}     = {};
    $index->{packages} = {};
    $index->{files}    = {};
    my $doc = PLS::Parser::Document->new(path => $uri->file);

    isa_ok($doc,             'PLS::Parser::Document');
    isa_ok($doc->{document}, 'PPI::Document');
    isa_ok($doc->{index},    'PLS::Parser::Index');
};

subtest 'new without path or uri' => sub {
    plan tests => 1;

    my $doc = PLS::Parser::Document->new();
    ok(!defined($doc), 'no document returned without path or uri');
};

subtest 'new with bad path' => sub {
    plan tests => 1;

    my $temp = File::Temp->new(unlink => 0);
    close $temp;
    unlink $temp->filename;
    my $doc = PLS::Parser::Document->new(path => $temp->filename);
    ok(!defined($doc), 'no document returned with nonexistent path');
};

subtest 'new with bad uri' => sub {
    plan tests => 1;

    my $temp = File::Temp->new(unlink => 0);
    close $temp;
    unlink $temp->filename;
    my $uri = URI::file->new($temp->filename);
    my $doc = PLS::Parser::Document->new(uri => $uri->as_string);
    ok(!defined($doc), 'no document returned with nonexistent uri');
};
