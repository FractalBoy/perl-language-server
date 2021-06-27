package PLS::Server::Request::TextDocument::DidChange;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Parser::Document;

=head1 NAME

PLS::Server::Request::TextDocument::DidChange

=head1 DESCRIPTION

This is a notification from the client to the server that
a text document was changed.

=cut

sub service
{
    my ($self) = @_;

    return unless (ref $self->{params}{contentChanges} eq 'ARRAY');
    PLS::Parser::Document->update_file(uri => $self->{params}{textDocument}{uri}, changes => $self->{params}{contentChanges});

    return;
}

1;
