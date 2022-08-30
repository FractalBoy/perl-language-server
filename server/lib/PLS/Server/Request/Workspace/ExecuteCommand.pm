package PLS::Server::Request::Workspace::ExecuteCommand;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Parser::Document;
use PLS::Server::Request::Workspace::ApplyEdit;

=head1 NAME

PLS::Server::Request::Workspace::ExecuteCommand

=head1 DESCRIPTION

This is a message from the client to the server requesting that a
command be executed.

The commands that are currently implemented are:

=over

=item pls.sortImports

This sorts the imports of the current Perl file. The sorting follows this order:

=over

=item C<use strict> and C<use warnings>

=item C<use parent> and C<use base>

=item Other pragmas (excluding C<use constant>)

=item Core and external imports

=item Internal imports (from the current project)

=item Constants (C<use constant>)

=back

This command is not perfect and is a work in progress. It does not handle
comments or non-contiguous imports well.

=back

=cut

sub service
{
    my ($self, $server) = @_;

    if ($self->{params}{command} eq 'pls.sortImports')
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
          if (ref $doc ne 'PLS::Parser::Document');
        my ($new_text, $lines) = $doc->sort_imports();

        $server->send_server_request(PLS::Server::Request::Workspace::ApplyEdit->new(text => $new_text, path => $file, lines => $lines));
    } ## end if ($self->{params}{command...})

    return PLS::Server::Response->new({id => $self->{id}, result => undef});
} ## end sub service

1;
