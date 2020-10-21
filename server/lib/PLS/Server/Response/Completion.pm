package PLS::Server::Response::Completion;
use parent q(PLS::Server::Response);

use strict;

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}, result => undef};

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});
    my @elements = $document->find_elements_at_location(@{$request->{params}{position}}{qw(line character)});
    my ($word)   = sort { length $a->name <=> length $b->name } grep { $_->{ppi_element}->significant } @elements;

    return $self unless (ref $word eq 'PLS::Parser::Element');

    my $name     = $word->name;
    my $subs     = $document->{index}{cache}{subs_trie}->find($name);
    my $packages = $document->{index}{cache}{packages_trie}->find($name);

    $subs     = [] unless (ref $subs eq 'ARRAY');
    $packages = [] unless (ref $packages eq 'ARRAY');
    return $self if (not scalar @$subs and not scalar @$packages);

    $self->{result} = [(map { {label => $_, kind => 3} } @$subs), (map { {label => $_, kind => 7} } @$packages)];
    @{$self->{result}} = map
    {
        { %$_, textEdit => {newText => $_->{label}, range => $word->range} }
    } @{$self->{result}};

    return $self;
} ## end sub new

1;
