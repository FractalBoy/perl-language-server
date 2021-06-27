package PLS::Server::Response::Hover;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use PLS::Parser::Document;

=head1 NAME

PLS::Server::Response::Hover

=head1 DESCRIPTION

This is a message from the server to the client with
documentation for the location the mouse is currently hovering.

=cut

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
                                         character => $pod->column_number + length $pod->{element}->content,
                                        }
                                }
                      };

    return $self;
} ## end sub new

1;
