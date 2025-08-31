#!perl

use Test2::V0;

plan tests => 72;

use ok 'PLS';
use ok 'PLS::JSON';
use ok 'PLS::Server';

use ok 'PLS::Server::Cache';

use ok 'PLS::Server::Method::CompletionItem';
use ok 'PLS::Server::Method::ServerMethod';
use ok 'PLS::Server::Method::TextDocument';
use ok 'PLS::Server::Method::Workspace';

use ok 'PLS::Server::Request::Client::RegisterCapability';

use ok 'PLS::Server::Request::CompletionItem::Resolve';

use ok 'PLS::Server::Request::TextDocument::PublishDiagnostics';

use ok 'PLS::Server::Request::TextDocument::Completion';
use ok 'PLS::Server::Request::TextDocument::Definition';
use ok 'PLS::Server::Request::TextDocument::DidChange';
use ok 'PLS::Server::Request::TextDocument::DidClose';
use ok 'PLS::Server::Request::TextDocument::DidOpen';
use ok 'PLS::Server::Request::TextDocument::DidSave';
use ok 'PLS::Server::Request::TextDocument::DocumentSymbol';
use ok 'PLS::Server::Request::TextDocument::Formatting';
use ok 'PLS::Server::Request::TextDocument::Hover';
use ok 'PLS::Server::Request::TextDocument::RangeFormatting';
use ok 'PLS::Server::Request::TextDocument::SignatureHelp';

use ok 'PLS::Server::Request::Workspace::ApplyEdit';
use ok 'PLS::Server::Request::Workspace::Configuration';
use ok 'PLS::Server::Request::Workspace::DidChangeConfiguration';
use ok 'PLS::Server::Request::Workspace::DidChangeWatchedFiles';
use ok 'PLS::Server::Request::Workspace::DidChangeWorkspaceFolders';
use ok 'PLS::Server::Request::Workspace::ExecuteCommand';
use ok 'PLS::Server::Request::Workspace::Symbol';

use ok 'PLS::Server::Request::Window::WorkDoneProgress::Create';

use ok 'PLS::Server::Request::CancelRequest';
use ok 'PLS::Server::Request::Factory';
use ok 'PLS::Server::Request::Initialize';
use ok 'PLS::Server::Request::Initialized';
use ok 'PLS::Server::Request::Shutdown';
use ok 'PLS::Server::Request::Exit';
use ok 'PLS::Server::Request::Progress';

use ok 'PLS::Server::Response::Cancelled';
use ok 'PLS::Server::Response::Completion';
use ok 'PLS::Server::Response::DocumentSymbol';
use ok 'PLS::Server::Response::Formatting';
use ok 'PLS::Server::Response::Hover';
use ok 'PLS::Server::Response::InitializeResult';
use ok 'PLS::Server::Response::Location';
use ok 'PLS::Server::Response::RangeFormatting';
use ok 'PLS::Server::Response::Resolve';
use ok 'PLS::Server::Response::ServerNotInitialized';
use ok 'PLS::Server::Response::SignatureHelp';
use ok 'PLS::Server::Response::WorkspaceSymbols';
use ok 'PLS::Server::Response::Shutdown';
use ok 'PLS::Server::Response::InvalidRequest';

use ok 'PLS::Server::Message';
use ok 'PLS::Server::Request';
use ok 'PLS::Server::Response';
use ok 'PLS::Server::State';

use ok 'PLS::Parser::Document';
use ok 'PLS::Parser::DocumentSymbols';
use ok 'PLS::Parser::Index';
use ok 'PLS::Parser::PackageSymbols';

use ok 'PLS::Parser::Pod';
use ok 'PLS::Parser::Pod::Builtin';
use ok 'PLS::Parser::Pod::ClassMethod';
use ok 'PLS::Parser::Pod::Method';
use ok 'PLS::Parser::Pod::Package';
use ok 'PLS::Parser::Pod::Subroutine';
use ok 'PLS::Parser::Pod::Variable';

use ok 'PLS::Parser::Element';
use ok 'PLS::Parser::Element::Constant';
use ok 'PLS::Parser::Element::Package';
use ok 'PLS::Parser::Element::Subroutine';
use ok 'PLS::Parser::Element::Variable';
use ok 'PLS::Parser::Element::VariableStatement';
