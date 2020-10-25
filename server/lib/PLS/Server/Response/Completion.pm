package PLS::Server::Response::Completion;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use Pod::Functions;
use Module::CoreList;
use Module::Metadata;
use ExtUtils::Installed;

use PLS::Parser::Document;
use PLS::Parser::Pod;
use Trie;

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}, result => undef};

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});
    return $self unless (ref $document eq 'PLS::Parser::Document');

    my ($word, $arrow) = $document->find_word_under_cursor(@{$request->{params}{position}}{qw(line character)});
    return $self unless (ref $word eq 'PLS::Parser::Element');

    my $subs     = $document->{index}{subs_trie}->find($word->name);
    my $packages = $document->{index}{packages_trie}->find($word->name);

    # if we're on an arrow but the token before the arrow isn't actually a package,
    # then we really should be looking at the node after the arrow
    if ($arrow and ref $packages ne 'ARRAY' and ref $word->next_sibling eq 'PLS::Parser::Element')
    {
        # if there's no node after the arrow, we don't have anything to go on yet.
        return $self unless (ref $word->next_sibling->next_sibling eq 'PLS::Parser::Element');
        $word = $word->next_sibling->next_sibling;

        $subs     = $document->{index}{subs_trie}->find($word->name);
        $packages = $document->{index}{packages_trie}->find($word->name);
    }

    my @results;
    my %seen_subs;

    foreach my $family (keys %Pod::Functions::Kinds)
    {
        foreach my $sub (@{$Pod::Functions::Kinds{$family}})
        {
            next if $sub =~ /\s+/;
            next if $seen_subs{$sub}++;
            push @results,
              {
                label => $sub,
                kind  => 3
              };
        } ## end foreach my $sub (@{$Pod::Functions::Kinds...})
    } ## end foreach my $family (keys %Pod::Functions::Kinds...)

    foreach my $module (Module::CoreList->find_modules(qr//, $]))
    {
        push @results,
          {
            label => $module,
            kind  => 7
          };
    } ## end foreach my $module (Module::CoreList...)

    my $include = PLS::Parser::Pod->get_clean_inc();
    my $extutils = ExtUtils::Installed->new(inc_override => $include);

    foreach my $module ($extutils->modules)
    {
        push @results,
          {
            label => $module,
            kind  => 7
          };
    } ## end foreach my $module ($extutils...)

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

            # add other variable forms to the list for arrays and hashes
            if ($variable->name =~ /^[\@\%]/)
            {
                my $name = $variable->name =~ s/^[\@\%]/\$/r;
                push @results,
                  {
                    label  => $name,
                    kind   => 6,
                    append => $variable->name =~ /^\@/ ? '[' : '{'
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

    # check to see if we can import it
    eval 'require ' . $word->name;

    unless (length $@)
    {
        my $potential_package = Module::Metadata->new_from_module($word->name);
        if (ref $potential_package eq 'Module::Metadata')
        {
            my $doc = PLS::Parser::Document->new(path => $potential_package->filename);
            next unless (ref $doc eq 'PLS::Parser::Document');
            foreach my $sub (@{$doc->get_subroutines()})
            {
                push @results,
                  {
                    label => $word->name . ($arrow ? '->' : '') . $sub->name,
                    kind  => 3
                  };
            } ## end foreach my $sub (@{$doc->get_subroutines...})
        } ## end if (ref $potential_package...)
    } ## end unless ($@)

    $subs     = [] unless (ref $subs eq 'ARRAY');
    $packages = [] unless (ref $packages eq 'ARRAY');

    @$subs     = map { {label => $_, kind => 3} } @$subs;
    @$packages = map { {label => $_, kind => 7} } @$packages;

    @results = (@results, @$subs, @$packages);

    $self->{result} = [
        map {
            { %$_, textEdit => {newText => $_->{label} . ($_->{append} // ''), range => $word->range}, data => $request->{params}{textDocument}{uri} }
          } @results
    ];

    return $self;
} ## end sub new

1;
