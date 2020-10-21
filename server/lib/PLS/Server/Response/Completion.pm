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

    my @results;

    foreach my $sub (@{$document->get_subroutines()})
    {
        push @results,
          {
            label => $sub->name,
            kind  => 3
          };
    } ## end foreach my $sub (@{$document...})

    foreach my $constant (@{$document->get_constants()})
    {
        push @results,
          {
            label => $constant->name,
            kind  => 21
          };
    } ## end foreach my $constant (@{$document...})

    foreach my $statement (@{$document->get_variable_statements()})
    {
        foreach my $variable (@{$statement->{symbols}})
        {
            push @results,
              {
                label => $variable->name,
                kind  => 6
              };

            if ($variable->name =~ /^\@/ or $variable->name =~ /^\%/)
            {
                my $name = $variable->name =~ s/^[\@\%]/\$/r;
                push @results,
                  {
                    label  => $name,
                    kind   => 6,
                    append => $variable->name =~ /^@/ ? '[' : '{'
                  };
            } ## end if ($variable->name =~...)
        } ## end foreach my $variable (@{$statement...})
    } ## end foreach my $statement (@{$document...})

    foreach my $package (@{$document->get_packages()})
    {
        push @results,
          {
            label => $package->name,
            kind  => 7
          };
    } ## end foreach my $package (@{$document...})

    foreach my $sub (keys %{$document->{index}{cache}{subs}})
    {
        push @results,
          {
            label => $sub,
            kind  => 3
          };
    } ## end foreach my $sub (keys %{$document...})

    foreach my $package (keys %{$document->{index}{cache}{packages}})
    {
        push @results,
          {
            label => $package,
            kind  => 7
          };
    } ## end foreach my $package (keys %...)

    $self->{result} = [
        map {
            { %$_, textEdit => {newText => $_->{label} . $_->{append}, range => $word->range} }
          } @results
    ];

    return $self;
} ## end sub new

1;
