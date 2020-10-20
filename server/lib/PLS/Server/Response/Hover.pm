package PLS::Server::Response::Hover;
use parent q(PLS::Server::Response);

use strict;
use warnings;

use Pod::Find;
use Pod::Markdown;
use URI;

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my $self = bless {
                      id     => $request->{id},
                      result => undef
                     }, $class;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});
    my ($ok, $pod) = $document->find_pod(@{$request->{params}{position}}{qw(line character)});
    return $self unless $ok;

    $self->{result} = {
                       contents => {kind => 'markdown', value => ${$pod->{markdown}}},
                       range    => {
                                 start => {
                                           line      => $pod->line_number,
                                           character => $pod->column_number,
                                          },
                                 end => {
                                         line      => $pod->line_number,
                                         character => $pod->column_number + length $pod->name,
                                        }
                                }
                      };

    return $self;
} ## end sub new

1;
