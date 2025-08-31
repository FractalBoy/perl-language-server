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

plan tests => 38;

my $text = do { local $/; <DATA> };

# Cache workspace folders
PLS::Parser::Index->new(workspace_folders => [$FindBin::RealBin]);

my $uri = URI::file->new(File::Spec->catfile($FindBin::RealBin, File::Basename::basename($0)));
PLS::Parser::Document->open_file(uri => $uri->as_string, text => $text, languageId => 'perl');

subtest 'sigil only' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 0);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 1);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 0; end() };
            field end   => hash { field line => 0; field character => 1; end() };
            end()
        },
        'correct range'
      );
    is($arrow, F(), 'no arrow');
    isnt($package, L(), 'no package');
    is($filter, '$', 'filter correct');
}; ## end 'sigil only' => sub

subtest 'partial variable name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 1);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 0; end() };
            field end   => hash { field line => 0; field character => 2; end() };
            end()
        },
        'correct range'
      );
    is($arrow, F(), 'no arrow');
    isnt($package, L(), 'no package');
    is($filter, '$o', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'partial variable name' => sub

subtest 'arrow without method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 2);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 6);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 6; end() };
            field end   => hash { field line => 0; field character => 6; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           T(), 'arrow');
    is(length($package), F(), 'no package');
    is($filter,          '',  'filter correct');
}; ## end 'arrow without method name' => sub

subtest 'arrow with method name start' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 3);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 7);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 6; end() };
            field end   => hash { field line => 0; field character => 7; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           T(), 'arrow');
    is(length($package), F(), 'no package');
    is($filter,          'm', 'filter correct');
}; ## end 'arrow with method name start' => sub

subtest 'arrow with full method name chained to blank method' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 4);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 14);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 14; end() };
            field end   => hash { field line => 0; field character => 14; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           T(), 'arrow');
    is(length($package), F(), 'no package');
    is($filter,          '',  'filter correct');
}; ## end 'arrow with full method name chained to blank method' => sub

subtest 'arrow with full method name chained to method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 5);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 14);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 14; end() };
            field end   => hash { field line => 0; field character => 15; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           T(), 'arrow');
    is(length($package), F(), 'no package');
    is($filter,          'm', 'filter correct');
}; ## end 'arrow with full method name chained to method name' => sub

subtest 'package name start, one colon' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 6);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 0; end() };
            field end   => hash { field line => 0; field character => 5; end() };
            end()
        },
        'correct range'
      );
    is($arrow,   F(),     'no arrow');
    is($package, 'File:', 'package correct');
    is($filter,  'File',  'filter correct');
}; ## end 'package name start, one colon' => sub

subtest 'package name start, two colons' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 7);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 6);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 0; end() };
            field end   => hash { field line => 0; field character => 6; end() };
            end()
        },
        'correct range'
      );
    is($arrow,   F(),      'no arrow');
    is($package, 'File::', 'package correct');
    is($filter,  'File',   'filter correct');
}; ## end 'package name start, two colons' => sub

subtest 'class method arrow without method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 8);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 12);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 12; end() };
            field end   => hash { field line => 0; field character => 12; end() };
            end()
        },
        'correct range'
      );
    is($arrow,   T(),          'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  '',           'filter correct');
}; ## end 'class method arrow without method name' => sub

subtest 'class method arrow with start of method name' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 9);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 13);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 12; end() };
            field end   => hash { field line => 0; field character => 13; end() };
            end()
        },
        'correct range'
      );
    is($arrow,   T(),          'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  'c',          'filter correct');
}; ## end 'class method arrow with start of method name' => sub

subtest 'bareword function name only' => sub {

    # testing many of the various letter operators as start of function name
    my @tests = (
                 {line => 12, filter => 'm'},
                 {line => 13, filter => 's'},
                 {line => 14, filter => 'q'},
                 {line => 15, filter => 'qq'},
                 {line => 16, filter => 'qr'},
                 {line => 17, filter => 'qw'},
                 {line => 18, filter => 'qx'},
                 {line => 19, filter => 'func'}
                );

    plan tests => scalar @tests;

    foreach my $test (@tests)
    {
        subtest "line $test->{line}, filter $test->{filter}" => sub {
            plan tests => 5;

            my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => $test->{line});
            is($doc, check_isa('PLS::Parser::Document'), 'valid document');
            my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, length($test->{filter}));
            is(
                $range, hash
                {
                    field start => hash { field line => 0; field character => 0;                      end() };
                    field end   => hash { field line => 0; field character => length $test->{filter}; end() };
                    end()
                },
                'correct range'
              );
            is($arrow, F(), 'no arrow');

            is($package, $test->{filter}, 'correct package');
            is($filter,  $test->{filter}, 'filter correct');
        } ## end sub

    } ## end foreach my $test (@tests)
}; ## end 'bareword function name only' => sub

subtest 'start of package inside function parentheses' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 20);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 11);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 5;  end() };
            field end   => hash { field line => 0; field character => 11; end() };
            end()
        },
        'correct range'
      );
    is($arrow,   F(),      'no arrow');
    is($package, 'File::', 'package correct');
    is($filter,  'File',   'filter correct');
}; ## end 'start of package inside function parentheses' => sub

subtest 'start of package inside method parentheses' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 21);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 19);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 13; end() };
            field end   => hash { field line => 0; field character => 19; end() };
            end()
        },
        'correct range'
      );
    is($arrow,   F(),      'no arrow');
    is($package, 'File::', 'package correct');
    is($filter,  'File',   'filter correct');
}; ## end 'start of package inside method parentheses' => sub

subtest 'class method arrow without method name inside method parentheses' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 22);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 25);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 25; end() };
            field end   => hash { field line => 0; field character => 25; end() };
            end()
        },
        'correct range'
      );
    is($arrow,   T(),          'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  '',           'filter correct');
}; ## end 'class method arrow without method name inside method parentheses' => sub

subtest 'class method arrow with start of method name inside method parentheses' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 23);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 26);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 25; end() };
            field end   => hash { field line => 0; field character => 26; end() };
            end()
        },
        'correct range'
      );
    is($arrow,   T(),          'arrow');
    is($package, 'File::Spec', 'package correct');
    is($filter,  'c',          'filter correct');
}; ## end 'class method arrow with start of method name inside method parentheses' => sub

subtest 'variable typed before another variable' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 24);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');
    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 0; end() };
            field end   => hash { field line => 0; field character => 2; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable typed before another variable' => sub

subtest 'only sigil before arrow' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 25);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 1);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 0; end() };
            field end   => hash { field line => 0; field character => 1; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');

}; ## end 'only sigil before arrow' => sub

subtest 'only sigil before close paren' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 26);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 1; end() };
            field end   => hash { field line => 0; field character => 2; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'only sigil before close paren' => sub

subtest 'only sigil before close curly brace' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 27);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 1; end() };
            field end   => hash { field line => 0; field character => 2; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'only sigil before close curly brace' => sub

subtest 'only sigil before comma' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 28);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 1; end() };
            field end   => hash { field line => 0; field character => 2; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'only sigil before comma' => sub

subtest 'two arrows in a row' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 29);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 6);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 6; end() };
            field end   => hash { field line => 0; field character => 6; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           T(), 'arrow');
    is(length($package), F(), 'no package');
    is($filter,          '',  'filter correct');
}; ## end 'two arrows in a row' => sub

subtest 'fill method name between arrows' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 30);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 7);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 6; end() };
            field end   => hash { field line => 0; field character => 7; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           T(), 'arrow');
    is(length($package), F(), 'no package');
    is($filter,          'm', 'filter correct');
}; ## end 'fill method name between arrows' => sub

subtest 'sigil between double quotes' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 31);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 2);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 1; end() };
            field end   => hash { field line => 0; field character => 2; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'sigil between double quotes' => sub

subtest 'variable between double quotes' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 32);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 3);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 1; end() };
            field end   => hash { field line => 0; field character => 3; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable between double quotes' => sub

subtest 'sigil in qr' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 33);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 3; end() };
            field end   => hash { field line => 0; field character => 4; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'sigil in qr' => sub

subtest 'variable in qr' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 34);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 3; end() };
            field end   => hash { field line => 0; field character => 5; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable in qr' => sub

subtest 'sigil in qx' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 35);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 3; end() };
            field end   => hash { field line => 0; field character => 4; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'sigil in qx' => sub

subtest 'variable in qx' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 36);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 3; end() };
            field end   => hash { field line => 0; field character => 5; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable in qx' => sub

subtest 'sigil in qq' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 37);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 3; end() };
            field end   => hash { field line => 0; field character => 4; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'sigil in qq' => sub

subtest 'variable in qq' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 38);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 3; end() };
            field end   => hash { field line => 0; field character => 5; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable in qq' => sub

subtest 'sigil in s' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 39);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 3);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 2; end() };
            field end   => hash { field line => 0; field character => 3; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'sigil in s' => sub

subtest 'variable in s' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 40);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 2; end() };
            field end   => hash { field line => 0; field character => 4; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable in s' => sub

subtest 'sigil in m' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 41);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 3);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 2; end() };
            field end   => hash { field line => 0; field character => 3; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'sigil in m' => sub

subtest 'variable in m' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 42);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 2; end() };
            field end   => hash { field line => 0; field character => 4; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable in m' => sub

subtest 'sigil in y' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 43);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 3);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 2; end() };
            field end   => hash { field line => 0; field character => 3; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'sigil in y' => sub

subtest 'variable in y' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 44);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 2; end() };
            field end   => hash { field line => 0; field character => 4; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable in y' => sub

subtest 'sigil in tr' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 45);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 4);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 3; end() };
            field end   => hash { field line => 0; field character => 4; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(), 'no arrow');
    is(length($package), F(), 'no package');
    is($filter,          '$', 'filter correct');
}; ## end 'sigil in tr' => sub

subtest 'variable in tr' => sub {
    plan tests => 5;

    my $doc = PLS::Parser::Document->new(uri => $uri->as_string, line => 46);
    is($doc, check_isa('PLS::Parser::Document'), 'valid document');

    my ($range, $arrow, $package, $filter) = $doc->find_word_under_cursor(1, 5);
    is(
        $range, hash
        {
            field start => hash { field line => 0; field character => 3; end() };
            field end   => hash { field line => 0; field character => 5; end() };
            end()
        },
        'correct range'
      );
    is($arrow,           F(),  'no arrow');
    is(length($package), F(),  'no package');
    is($filter,          '$x', 'filter correct');    ## no critic (RequireInterpolationOfMetachars)
}; ## end 'variable in tr' => sub

__END__
$
$o
$obj->
$obj->m
$obj->method->
$obj->method->m
File:
File::
File::Spec->
File::Spec->c
File::Spec->catfile->
File::Spec->catfile->m
m
s
q
qq
qr
qw
qx
func
func(File::)
$obj->method(File::)
$obj->method(File::Spec->)
$obj->method(File::Spec->c)
$x$obj
$->method
($)
{$}
($,$y)
$obj->->method()
$obj->m->method()
"$"
"$x"
qr/$/
qr/$x/
qx($)
qx($x)
qq{$}
qq{$x}
s/$/
s/$x/
m<$>
m<$x>
y/$/
y/$x/
tr[$]
tr[$x]
