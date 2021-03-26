package PLS::Server::Response::Resolve;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use PLS::Parser::Document;

sub new
{
    my ($class, $request) = @_;

    my $self = {id => $request->{id}, result => undef};
    bless $self, $class;

    my $index = PLS::Parser::Document->get_index();
    return $self unless (ref $index eq 'PLS::Parser::Index');

    my $kind = $request->{params}{kind};

    if ($kind == 7)
    {
        my $pod = PLS::Parser::Pod::Package->new(index => $index, package => $request->{params}{label});
        my $ok  = $pod->find();

        if ($ok)
        {
            $self->{result} = $request->{params};
            $self->{result}{documentation} = {kind => 'markdown', value => ${$pod->{markdown}}};
        }
    } ## end if ($kind == 7)
    elsif ($kind == 3 or $kind == 21 or $kind == 14)
    {
        my ($package, $subroutine);

        if ($request->{params}{label} =~ /->/ or ($request->{params}{sortText} // '') =~ /->/)
        {
            my $label = $request->{params}{label} =~ /->/ ? $request->{params}{label} : $request->{params}{sortText};
            ($package, $subroutine) = split /->/, $label;
        }
        elsif ($request->{params}{label} =~ /::/ or ($request->{params}{filterText} // '') =~ /::/)
        {
            my $label = $request->{params}{label} =~ /::/ ? $request->{params}{label} : $request->{params}{filterText};
            my @parts = split /::/, $label;
            $subroutine = pop @parts;
            $package    = join '::', @parts;
        } ## end elsif ($request->{params}...)
        else
        {
            $subroutine = $request->{params}{label};
        }

        my $pod = PLS::Parser::Pod::Subroutine->new(index => $index, package => $package, subroutine => $subroutine);
        my $ok  = $pod->find();

        if ($ok)
        {
            $self->{result} = $request->{params};
            $self->{result}{documentation} = {kind => 'markdown', value => ${$pod->{markdown}}};
        }
    } ## end elsif ($kind == 3 or $kind...)

    return $self;
} ## end sub new

1;
