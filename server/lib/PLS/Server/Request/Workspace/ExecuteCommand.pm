package PLS::Server::Request::Workspace::ExecuteCommand;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Parser::Document;
use PLS::Server::Request::Workspace::ApplyEdit;

sub service
{
    my ($self, $server) = @_;

    if ($self->{params}{command} eq 'perl.sortImports')
    {
        my $file = $self->{params}{arguments}[0]{path};
        my $doc  = PLS::Parser::Document->new(path => $file);
        return
          PLS::Server::Response->new(
                                     {
                                      id    => $self->{id},
                                      error => {
                                                code    => -32602,
                                                message => 'Failed to sort imports.',
                                                data    => $file
                                               }
                                     }
                                    )
          unless (ref $doc eq 'PLS::Parser::Document');
        my ($new_text, $lines) = $doc->sort_imports();

        $server->{server_requests}->put(PLS::Server::Request::Workspace::ApplyEdit->new(text => $new_text, path => $file, lines => $lines))
    } ## end if ($self->{params}{command...})

    return PLS::Server::Response->new({id => $self->{id}, result => undef});
} ## end sub service

1;
