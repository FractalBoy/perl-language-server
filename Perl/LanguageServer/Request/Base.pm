package Perl::LanguageServer::Request::Base;

sub new {
    my ($class, $request) = @_;

    return bless $request, $class;
}

sub service {
    return undef;
}

1;