#!perl

use strict;
use warnings;

use Test::More tests => 72;

use_ok('PLS');
use_ok('PLS::JSON');
use_ok('PLS::Server');

use_ok('PLS::Server::Cache');

use_ok('PLS::Server::Method::CompletionItem');
use_ok('PLS::Server::Method::ServerMethod');
use_ok('PLS::Server::Method::TextDocument');
use_ok('PLS::Server::Method::Workspace');

use_ok('PLS::Server::Request::Client::RegisterCapability');

use_ok('PLS::Server::Request::CompletionItem::Resolve');

use_ok('PLS::Server::Request::TextDocument::PublishDiagnostics');

use_ok('PLS::Server::Request::TextDocument::Completion');
use_ok('PLS::Server::Request::TextDocument::Definition');
use_ok('PLS::Server::Request::TextDocument::DidChange');
use_ok('PLS::Server::Request::TextDocument::DidClose');
use_ok('PLS::Server::Request::TextDocument::DidOpen');
use_ok('PLS::Server::Request::TextDocument::DidSave');
use_ok('PLS::Server::Request::TextDocument::DocumentSymbol');
use_ok('PLS::Server::Request::TextDocument::Formatting');
use_ok('PLS::Server::Request::TextDocument::Hover');
use_ok('PLS::Server::Request::TextDocument::RangeFormatting');
use_ok('PLS::Server::Request::TextDocument::SignatureHelp');

use_ok('PLS::Server::Request::Workspace::ApplyEdit');
use_ok('PLS::Server::Request::Workspace::Configuration');
use_ok('PLS::Server::Request::Workspace::DidChangeConfiguration');
use_ok('PLS::Server::Request::Workspace::DidChangeWatchedFiles');
use_ok('PLS::Server::Request::Workspace::DidChangeWorkspaceFolders');
use_ok('PLS::Server::Request::Workspace::ExecuteCommand');
use_ok('PLS::Server::Request::Workspace::Symbol');

use_ok('PLS::Server::Request::Window::WorkDoneProgress::Create');

use_ok('PLS::Server::Request::CancelRequest');
use_ok('PLS::Server::Request::Factory');
use_ok('PLS::Server::Request::Initialize');
use_ok('PLS::Server::Request::Initialized');
use_ok('PLS::Server::Request::Shutdown');
use_ok('PLS::Server::Request::Exit');
use_ok('PLS::Server::Request::Progress');

use_ok('PLS::Server::Response::Cancelled');
use_ok('PLS::Server::Response::Completion');
use_ok('PLS::Server::Response::DocumentSymbol');
use_ok('PLS::Server::Response::Formatting');
use_ok('PLS::Server::Response::Hover');
use_ok('PLS::Server::Response::InitializeResult');
use_ok('PLS::Server::Response::Location');
use_ok('PLS::Server::Response::RangeFormatting');
use_ok('PLS::Server::Response::Resolve');
use_ok('PLS::Server::Response::ServerNotInitialized');
use_ok('PLS::Server::Response::SignatureHelp');
use_ok('PLS::Server::Response::WorkspaceSymbols');
use_ok('PLS::Server::Response::Shutdown');
use_ok('PLS::Server::Response::InvalidRequest');

use_ok('PLS::Server::Message');
use_ok('PLS::Server::Request');
use_ok('PLS::Server::Response');
use_ok('PLS::Server::State');

use_ok('PLS::Parser::Document');
use_ok('PLS::Parser::DocumentSymbols');
use_ok('PLS::Parser::Index');
use_ok('PLS::Parser::PackageSymbols');

use_ok('PLS::Parser::Pod');
use_ok('PLS::Parser::Pod::Builtin');
use_ok('PLS::Parser::Pod::ClassMethod');
use_ok('PLS::Parser::Pod::Method');
use_ok('PLS::Parser::Pod::Package');
use_ok('PLS::Parser::Pod::Subroutine');
use_ok('PLS::Parser::Pod::Variable');

use_ok('PLS::Parser::Element');
use_ok('PLS::Parser::Element::Constant');
use_ok('PLS::Parser::Element::Package');
use_ok('PLS::Parser::Element::Subroutine');
use_ok('PLS::Parser::Element::Variable');
use_ok('PLS::Parser::Element::VariableStatement');
