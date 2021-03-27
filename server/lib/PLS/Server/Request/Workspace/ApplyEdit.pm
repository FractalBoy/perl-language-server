package PLS::Server::Request::Workspace::ApplyEdit;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use URI;

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
