package PLS::Server::Request::TextDocument::DidClose;

use strict;
use warnings;

use parent 'PLS::Server::Request::Base';

use PLS::Parser::Document;

sub service
{
    my ($self) = @_;

    my $text_document = $self->{params}{textDocument};
    PLS::Parser::Document->close_file(%{$text_document}); 

    return;
}

1;
