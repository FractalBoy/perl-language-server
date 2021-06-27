package PLS::Server::Method::TextDocument;

use strict;
use warnings;

use PLS::Server::Request::TextDocument::Completion;
use PLS::Server::Request::TextDocument::Definition;
use PLS::Server::Request::TextDocument::DidChange;
use PLS::Server::Request::TextDocument::DidClose;
use PLS::Server::Request::TextDocument::DidOpen;
use PLS::Server::Request::TextDocument::DidSave;
use PLS::Server::Request::TextDocument::DocumentSymbol;
use PLS::Server::Request::TextDocument::Formatting;
use PLS::Server::Request::TextDocument::Hover;
use PLS::Server::Request::TextDocument::SignatureHelp;
use PLS::Server::Request::TextDocument::RangeFormatting;

=head1 NAME

PLS::Server::Method::Workspace

=head1 DESCRIPTION

This module redirects requests starting with C<textDocument/> to the appropriate
subclass of L<PLS::Server::Request> for the type of request.

Requests currently implemented:

=over

=item textDocument/definition - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_definition>

L<PLS::Server::Request::TextDocument::Definition>

=item textDocument/documentSymbol - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentSymbol>

L<PLS::Server::Request::TextDocument::DocumentSymbol>

=item textDocument/hover - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_hover>

L<PLS::Server::Request::TextDocument::Hover>

=item textDocument/signatureHelp - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_signatureHelp>

L<PLS::Server::Request::TextDocument::SignatureHelp>

=item textDocument/didOpen - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didOpen>

L<PLS::Server::Request::TextDocument::DidOpen>

=item textDocument/didChange - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didChange>

L<PLS::Server::Request::TextDocument::DidChange>

=item textDocument/didClose - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didClose>

L<PLS::Server::Request::TextDocument::DidClose>

=item textDocument/didSave - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didSave>

L<PLS::Server::Request::TextDocument::DidSave>

=item textDocument/formatting - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_formatting>

L<PLS::Server::Request::TextDocument::Formatting>

=item textDocument/rangeFormatting - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_rangeFormatting>

L<PLS::Server::Request::TextDocument::RangeFormatting>

=item textDocument/completion - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_completion>

L<PLS::Server::Request::TextDocument::Completion>

=back

=cut

sub get_request
{
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'definition')
    {
        return PLS::Server::Request::TextDocument::Definition->new($request);
    }
    if ($method eq 'documentSymbol')
    {
        return PLS::Server::Request::TextDocument::DocumentSymbol->new($request);
    }
    if ($method eq 'hover')
    {
        return PLS::Server::Request::TextDocument::Hover->new($request);
    }
    if ($method eq 'signatureHelp')
    {
        return PLS::Server::Request::TextDocument::SignatureHelp->new($request);
    }
    if ($method eq 'didOpen')
    {
        return PLS::Server::Request::TextDocument::DidOpen->new($request);
    }
    if ($method eq 'didChange')
    {
        return PLS::Server::Request::TextDocument::DidChange->new($request);
    }
    if ($method eq 'didClose')
    {
        return PLS::Server::Request::TextDocument::DidClose->new($request);
    }
    if ($method eq 'didSave')
    {
        return PLS::Server::Request::TextDocument::DidSave->new($request);
    }
    if ($method eq 'formatting')
    {
        return PLS::Server::Request::TextDocument::Formatting->new($request);
    }
    if ($method eq 'rangeFormatting')
    {
        return PLS::Server::Request::TextDocument::RangeFormatting->new($request);
    }
    if ($method eq 'completion')
    {
        return PLS::Server::Request::TextDocument::Completion->new($request);
    }
} ## end sub get_request

1;
