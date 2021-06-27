package PLS::Server::Request::Workspace::ApplyEdit;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use URI;

=head1 NAME

PLS::Server::Request::Workspace::ApplyEdit

=head1 DESCRIPTION

This is a message from the server to the client requesting that
an edit be made to one or more sections of one or more documents.

=cut

sub new
{
    my ($class, %args) = @_;

    my $uri  = URI::file->new($args{path})->as_string;
    my $text = $args{text};

    my $self = {
                method => 'workspace/applyEdit',
                params => {
                           edit => {
                                    changes => {
                                                $uri => [
                                                         {
                                                          range => {
                                                                    start => {line => 0,            character => 0},
                                                                    end   => {line => $args{lines}, character => 0}
                                                                   },
                                                          newText => $$text
                                                         }
                                                        ]
                                               }
                                   }
                          }
               };

    return bless $self, $class;
} ## end sub new

1;
