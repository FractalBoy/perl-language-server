package PLS::Server::Response::Completion;

use strict;
use warnings;

use parent q(PLS::Server::Response);
use feature 'state';

use Pod::Functions;
use Module::CoreList;
use Module::Metadata;
use ExtUtils::Installed;

use PLS::Parser::Document;
use PLS::Parser::PackageSymbols;
use PLS::Parser::Pod;

=head1 NAME

PLS::Server::Response::Completion

=head1 DESCRIPTION

This is a message from the server to the client with a list
of completion items for the current location.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}, result => undef}, $class;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri}, line => $request->{params}{position}{line});
    return $self unless (ref $document eq 'PLS::Parser::Document');

    my @word_under_cursor_info = $document->find_word_under_cursor(@{$request->{params}{position}}{qw(line character)});
    return $self unless (scalar @word_under_cursor_info);
    my ($range, $arrow, $package, $filter) = @word_under_cursor_info;
    my $retrieve_packages = not $arrow or $filter =~ /^[\$\%\@]/ ? 0 : 1;

    if (ref $range eq 'HASH')
    {
        $range->{start}{line} = $request->{params}{position}{line};
        $range->{end}{line}   = $request->{params}{position}{line};
    }

    return $self unless (ref $range eq 'HASH');
    $package =~ s/::$// if (length $package);

    my @results;
    my %seen_subs;
    my $functions = PLS::Parser::PackageSymbols::get_package_functions($package, $PLS::Server::State::CONFIG->{inc});

    if (ref $functions eq 'ARRAY')
    {
        my $separator = $arrow ? '->' : '::';

        foreach my $name (@{$functions})
        {
            next if $seen_subs{$name}++;

            my $fully_qualified = join $separator, $package, $name;
            my $result = {
                          label      => $name,
                          sortText   => $fully_qualified,
                          filterText => $fully_qualified,
                          kind       => 3
                         };

            if ($arrow)
            {
                $result->{insertText} = "->$name";
            }
            else
            {
                $result->{insertText} = $fully_qualified;
            }

            push @results, $result;
        } ## end foreach my $name (@{$functions...})
    } ## end if (ref $functions eq ...)

    my $subs = $document->{index}{subs_trie}->find($filter);
    my $packages = [];
    $packages = $document->{index}{packages_trie}->find($filter) if $retrieve_packages;
    state @keywords;

    my $full_text;
    my %seen_packages;

    unless ($filter =~ /^[\$\%\@]/)
    {
        if (scalar @keywords)
        {
            push @results, @keywords;
        }
        else
        {
            my %seen_keywords;

            foreach my $family (keys %Pod::Functions::Kinds)
            {
                foreach my $sub (@{$Pod::Functions::Kinds{$family}})
                {
                    next if $sub =~ /\s+/;
                    next if $seen_keywords{$sub}++;
                    push @keywords, {label => $sub, kind => 14};
                } ## end foreach my $sub (@{$Pod::Functions::Kinds...})
            } ## end foreach my $family (keys %Pod::Functions::Kinds...)

            foreach my $keyword (
                  qw(cmp continue default do else elsif eq for foreach ge given gt if le lock lt ne not or package sub unless until when while x xor))
            {
                next if $seen_keywords{$keyword}++;
                push @keywords, {label => $keyword, kind => 14};
            }

            push @results, @keywords;
        } ## end else [ if (scalar @builtins) ]

        $full_text = $document->get_full_text();

        foreach my $sub (@{$document->get_subroutines_fast($full_text)})
        {
            next if $seen_subs{$sub}++;
            push @results, {label => $sub, kind => 3};
        }

        my %seen_constants;

        foreach my $constant (@{$document->get_constants_fast($full_text)})
        {
            next if $seen_constants{$constant}++;
            push @results, {label => $constant, kind => 21};
        }

        if ($retrieve_packages)
        {
            foreach my $pack (@{$document->get_packages_fast($full_text)})
            {
                next if $seen_packages{$pack}++;
                push @results, {label => $pack, kind => 9};
            }
        } ## end if ($retrieve_packages...)
    } ## end unless ($filter =~ /^[\$\%\@]/...)

    # Can use state here, core and external modules unlikely to change.
    state $core_modules = [Module::CoreList->find_modules(qr//, $])];
    state $include      = PLS::Parser::Pod->get_clean_inc();
    state $ext_modules  = [ExtUtils::Installed->new(inc_override => $include)->modules];

    if ($retrieve_packages)
    {
        foreach my $module (@{$core_modules}, @{$ext_modules})
        {
            next if $seen_packages{$module}++;
            push @results,
              {
                label => $module,
                kind  => 7
              };
        } ## end foreach my $module (@{$core_modules...})
    } ## end if ($retrieve_packages...)

    my %seen_variables;

    # Add variables to the list if the current word is obviously a variable.
    if (not $arrow and not length $package and $filter =~ /^[\$\@\%]/)
    {
        $full_text = $document->get_full_text() unless (ref $full_text eq 'SCALAR');

        foreach my $variable (@{$document->get_variables_fast($full_text)})
        {
            next if $seen_variables{$variable}++;
            push @results,
              {
                label => $variable,
                kind  => 6
              };

            # add other variable forms to the list for arrays and hashes
            if ($variable =~ /^[\@\%]/)
            {
                my $name   = $variable =~ s/^[\@\%]/\$/r;
                my $append = $variable =~ /^\@/ ? '[' : '{';
                push @results,
                  {
                    label      => $variable,
                    insertText => $name . $append,
                    filterText => $name,
                    kind       => 6
                  };
            } ## end if ($variable =~ /^[\@\%]/...)
        } ## end foreach my $variable (@{$document...})
    } ## end if (not $arrow and not...)

    $subs     = [] unless (ref $subs eq 'ARRAY');
    $packages = [] unless (ref $packages eq 'ARRAY');

    @$subs     = map { {label => $_, kind => 3} } grep { not $seen_subs{$_}++ } @$subs;
    @$packages = map { {label => $_, kind => 7} } grep { not $seen_packages{$_}++ } @$packages;

    @results = (@results, @$subs, @$packages);

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
