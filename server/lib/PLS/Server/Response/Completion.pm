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

    my ($range, $arrow, $package, $filter) = $document->find_word_under_cursor(@{$request->{params}{position}}{qw(line character)});
    return $self unless (ref $range eq 'HASH');
    $package =~ s/::$// if (length $package);

    my $subs     = $document->{index}{subs_trie}->find($filter);
    my $packages = $document->{index}{packages_trie}->find($filter);

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
                my $append = $variable->name =~ /^\@/ ? '[' : '{';
                push @results,
                  {
                    label  => $variable->name,
                    insertText => $name . $append,
                    filterText => $name,
                    kind   => 6
                  };
            } ## end if ($variable->name =~...)
        } ## end foreach my $variable (@{$statement...})
    } ## end foreach my $statement (@{$document...})

    foreach my $pack (@{$document->get_packages()})
    {
        push @results,
          {
            label => $pack->name,
            kind  => 7
          };
    } ## end foreach my $pack (@{$document...})

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
        my $potential_package = Module::Metadata->new_from_module($package);

        if (ref $potential_package eq 'Module::Metadata')
        {
            my $doc = PLS::Parser::Document->new(path => $potential_package->filename);
            if (ref $doc eq 'PLS::Parser::Document')
            {
                foreach my $sub (@{$doc->get_subroutines()})
                {
                    my $separator = $arrow ? '->' : '::';
                    my $fully_qualified = join $separator, $package, $sub->name;
                    my $result = {
                                  label    => $sub->name,
                                  sortText => join($arrow ? '->' : '::', $package, $sub->name),
                                  kind     => 3,
                                 };
                    unless ($arrow)
                    {
                        $result->{filterText} = $fully_qualified;
                        $result->{insertText} = $fully_qualified;
                    }
                    push @results, $result;
                } ## end foreach my $sub (@{$doc->get_subroutines...})
            } ## end if (ref $doc eq 'PLS::Parser::Document'...)
        } ## end if (ref $potential_package...)
    } ## end if (length $package and...)

    $subs     = [] unless (ref $subs eq 'ARRAY');
    $packages = [] unless (ref $packages eq 'ARRAY');

    @$subs     = map { {label => $_, kind => 3} } @$subs;
    @$packages = map { {label => $_, kind => 7} } @$packages;

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
