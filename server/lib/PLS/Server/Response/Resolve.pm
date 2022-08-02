package PLS::Server::Response::Resolve;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use PLS::Parser::Index;
use PLS::Parser::Pod::Package;
use PLS::Parser::Pod::Subroutine;
use PLS::Parser::Pod::Builtin;

=head1 NAME

PLS::Server::Response::Resolve

=head1 DESCRIPTION

This is a message from the server to the client with documentation
about the currently selected completion item.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = {id => $request->{id}, result => undef};
    bless $self, $class;

    my $index = PLS::Parser::Index->new();
    my $kind  = $request->{params}{kind};

    if ($kind == 6)
    {
        my $pod = PLS::Parser::Pod::Variable->new(variable => $request->{params}{label});
        my $ok  = $pod->find();

        if ($ok)
        {
            $self->{result} = $request->{params};
            $self->{result}{documentation} = {kind => 'markdown', value => ${$pod->{markdown}}};
        }
    } ## end if ($kind == 6)
    elsif ($kind == 7)
    {
        my $pod = PLS::Parser::Pod::Package->new(index => $index, package => $request->{params}{label});
        my $ok  = $pod->find();

        if ($ok)
        {
            $self->{result} = $request->{params};
            $self->{result}{documentation} = {kind => 'markdown', value => ${$pod->{markdown}}};
        }
    } ## end elsif ($kind == 7)
    elsif ($kind == 3 or $kind == 21)
    {
        my ($package, $subroutine);

        if ($request->{params}{label} =~ /->/ or ($request->{params}{sortText} // '') =~ /->/)
        {
            my $label = $request->{params}{label} =~ /->/ ? $request->{params}{label} : $request->{params}{sortText};
            ($package, $subroutine) = split /->/, $label;
            $package = [$package];
        } ## end if ($request->{params}...)
        elsif ($request->{params}{label} =~ /::/ or ($request->{params}{filterText} // '') =~ /::/)
        {
            my $label = $request->{params}{label} =~ /::/ ? $request->{params}{label} : $request->{params}{filterText};
            my @parts = split /::/, $label;
            $subroutine = pop @parts;
            $package    = [join '::', @parts];
        } ## end elsif ($request->{params}...)
        else
        {
            $subroutine = $request->{params}{label};
            $package    = $request->{params}{data} if (ref $request->{params}{data} eq 'ARRAY');
        }

        my $pod = PLS::Parser::Pod::Subroutine->new(index => $index, packages => $package, subroutine => $subroutine);
        my $ok  = $pod->find();

        if ($ok)
        {
            $self->{result} = $request->{params};
            $self->{result}{documentation} = {kind => 'markdown', value => ${$pod->{markdown}}};
        }
    } ## end elsif ($kind == 3 or $kind...)
    elsif ($kind == 14)
    {
        my $pod = PLS::Parser::Pod::Builtin->new(function => $request->{params}{label});
        my $ok  = $pod->find();

        if ($ok)
        {
            $self->{result} = $request->{params};
            $self->{result}{documentation} = {kind => 'markdown', value => ${$pod->{markdown}}};
        }
    } ## end elsif ($kind == 14)

    return $self;
} ## end sub new

1;
