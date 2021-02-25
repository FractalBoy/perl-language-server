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

    my $self = bless {id => $request->{id}, result => undef}, $class;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri}, line => $request->{params}{position}{line});
    return $self unless (ref $document eq 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $document->find_word_under_cursor(@{$request->{params}{position}}{qw(line character)});

    if (ref $range eq 'HASH')
    {
        $range->{start}{line} = $request->{params}{position}{line};
        $range->{end}{line} = $request->{params}{position}{line};
    }

    return $self unless (ref $range eq 'HASH');
    $package =~ s/::$// if (length $package);

    my @results;
    my %seen_subs;

    if (length $package)
    {
        local $SIG{__WARN__} = sub { };

        # check to see if we can import it
        eval "require $package";

        if (length $@)
        {
            my @parts = split /::/, $package;
            $package = join '::', @parts[0 .. $#parts - 1];
            eval "require $package";
        } ## end if (length $@)
    } ## end if (length $package)

    if (length $package and not length $@)
    {
        my $separator    = $arrow ? '->' : '::';
        my $ref          = \%::;
        my @module_parts = split '::', $package;

        foreach my $part (@module_parts)
        {
            $ref = $ref->{"${part}::"};
        }

        foreach my $name (keys %{$ref})
        {
            next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|import$/;
            next unless $package->can($name);
            next if $seen_subs{$name}++;

            my $fully_qualified = join $separator, $package, $name;
            my $result = {
                          label    => $name,
                          sortText => $fully_qualified,
                          kind     => 3
                         };

            unless ($arrow)
            {
                $result->{filterText} = $fully_qualified;
                $result->{insertText} = $fully_qualified;
            }

            push @results, $result;
        } ## end foreach my $name (keys %{$ref...})
    } ## end if (length $package and...)
    else
    {
        my $subs     = $document->{index}{subs_trie}->find($filter);
        my $packages = $document->{index}{packages_trie}->find($filter);

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

        my $include  = PLS::Parser::Pod->get_clean_inc();
        my $extutils = ExtUtils::Installed->new(inc_override => $include);

        foreach my $module ($extutils->modules)
        {
            push @results,
              {
                label => $module,
                kind  => 7
              };
        } ## end foreach my $module ($extutils...)

        if (ref $subs ne 'ARRAY' or not scalar @{$subs})
        {
            foreach my $sub (@{$document->get_subroutines()})
            {
                next if $seen_subs{$sub->name}++;
                push @results,
                  {
                    label => $sub->name,
                    kind  => 3
                  };
            } ## end foreach my $sub (@{$document...})
        } ## end if (ref $subs ne 'ARRAY'...)

        my %seen_constants;

        if (ref $subs ne 'ARRAY' or not scalar @{$subs})
        {
            foreach my $constant (@{$document->get_constants()})
            {
                next if $seen_constants{$constant->name}++;
                push @results,
                  {
                    label => $constant->name,
                    kind  => 21
                  };
            } ## end foreach my $constant (@{$document...})
        } ## end if (ref $subs ne 'ARRAY'...)

        my %seen_variables;

        foreach my $statement (@{$document->get_variable_statements()})
        {
            foreach my $variable (@{$statement->{symbols}})
            {
                next if $seen_variables{$variable->name}++;
                push @results,
                  {
                    label => $variable->name,
                    kind  => 6
                  };

                # add other variable forms to the list for arrays and hashes
                if ($variable->name =~ /^[\@\%]/)
                {
                    my $name   = $variable->name =~ s/^[\@\%]/\$/r;
                    my $append = $variable->name =~ /^\@/ ? '[' : '{';
                    push @results,
                      {
                        label      => $variable->name,
                        insertText => $name . $append,
                        filterText => $name,
                        kind       => 6
                      };
                } ## end if ($variable->name =~...)
            } ## end foreach my $variable (@{$statement...})
        } ## end foreach my $statement (@{$document...})

        if (ref $packages ne 'ARRAY' or not scalar @{$packages})
        {
            foreach my $pack (@{$document->get_packages()})
            {
                push @results,
                  {
                    label => $pack->name,
                    kind  => 7
                  };
            } ## end foreach my $pack (@{$document...})
        } ## end if (ref $packages ne 'ARRAY'...)

        $subs     = [] unless (ref $subs eq 'ARRAY');
        $packages = [] unless (ref $packages eq 'ARRAY');

        @$subs     = map { {label => $_, kind => 3} } grep { not $seen_subs{$_}++ } @$subs;
        @$packages = map { {label => $_, kind => 7} } @$packages;

        @results = (@results, @$subs, @$packages);
    } ## end else [ if (length $package and...)]

    foreach my $result (@results)
    {
        my $new_text = $result->{label};
        $new_text = $result->{insertText} if (length $result->{insertText});
        delete $result->{insertText};

        push @{$self->{result}},
          {
            %$result,
            textEdit => {newText => $new_text, range => $range},
            data     => $request->{params}{textDocument}{uri}
          };
    } ## end foreach my $result (@results...)

    return $self;
} ## end sub new

1;
