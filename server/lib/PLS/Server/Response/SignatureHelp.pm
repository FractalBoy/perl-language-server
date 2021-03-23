package PLS::Server::Response::SignatureHelp;

use strict;
use warnings;

use feature 'isa';
no warnings 'experimental::isa';

use parent q(PLS::Server::Response);

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my ($line, $character) = @{$request->{params}{position}}{qw(line character)};
    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri}, line => $line);
    my @elements = $document->find_elements_at_location($line, $character);

    my $word;

    foreach my $element (@elements)
    {
        next unless $element->{ppi_element}->isa('PPI::Structure::List');
        $word = $element;

        while ($word isa 'PLS::Parser::Element' and not $word->{ppi_element} isa 'PPI::Token::Word')
        {
            $word = $element->previous_sibling;
        }
    } ## end foreach my $element (@elements...)

    my @signatures;

    if ($word isa 'PLS::Parser::Element' and $word->{ppi_element} isa 'PPI::Token::Word')
    {
        my $results = $document->search_elements_for_definition($line, $character, $word);
        @signatures = map { $_->{signature} } @{$results};
    }

    my $active_parameter = $document->get_list_index($request->{params}{position}{line}, $request->{params}{position}{character});

    my %self = (
                id     => $request->{id},
                result => scalar @signatures ? {signatures => \@signatures, activeParameter => $active_parameter} : undef
               );

    return bless \%self, $class;
} ## end sub new

1;
