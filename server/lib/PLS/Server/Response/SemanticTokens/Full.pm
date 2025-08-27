package PLS::Server::Response::SemanticTokens::Full;

use strict;
use warnings;

use parent 'PLS::Server::Response::SemanticTokens';

use PPR;
use PLS::Parser::Document;
use PLS::Parser::Index;

sub new
{
    my ($class, $request) = @_;

    use Data::Dumper;
    warn "SemanticTokens::Full request: " . Dumper($request);
    my $self = bless {id => $request->{id}, result => {data =>[]}}, $class;
    my $uri  = $request->{params}{textDocument}{uri};
    warn "getting semantic tokens for $uri\n";
    my $text = PLS::Parser::Document->text_from_uri($uri);

    if (ref $text ne 'SCALAR')
    {
        return $self;
    }

    my $line_offsets = PLS::Parser::Index->get_line_offsets($text);

    # 0: keyword 1: function 2: class 3: number 4: modifier

    my $supports_try_catch = 0;
    my $supports_state = 0;
    my $supports_isa = 0;
    my $supports_defer = 0;

    while (${$text} =~ /((?&PerlUseStatement))$PPR::GRAMMAR/g)
    {
        my (undef, $feature, $value) = split m{\s+}, $1;

        if ($feature ne 'feature')
        {
            next;
        }

        if ($value =~ /(v?[\d_\.]+)/)
        {
            my $version = eval { version->parse($value) };
            
            if ($version)
            {
                if ($version >= v5.10)
                {
                    $supports_state = 1;
                }
                if ($version >= v5.36)
                {
                    $supports_isa = 1;
                }
                if ($version >= v5.40)
                {
                    $supports_try_catch = 1;
                }
            }
        }
        if ($value =~ /try/)
        {
            $supports_try_catch = 1;
        }
    }

   my $previous_line = 0;
    my $previous_pos = 0;

    my $rx = qr/(?<try>(?&PerlTryCatchFinallyBlock))|(?<isa>(?&PerlBinaryExpression))$PPR::GRAMMAR/;

    while (${$text} =~ /$rx/g)
    {
        my $start = $-[0];

        if ($+{try} and $+{try} =~ /(try).*(catch).*(finally)?/s)
        {
            if (not $supports_try_catch)
            {
                next;
            }

            my $try_pos     = $start + $-[1];
            my $line = PLS::Parser::Index->get_line_by_offset($line_offsets, $try_pos);
            my $try_line = $line - $previous_line;
            $previous_line = $line;

            my $try_line_start = $line_offsets->[$line];
            my $try_offset = $try_pos - $try_line_start;

            if ($try_line == 0)
            {
                $try_offset -= $previous_pos;
            }

            push @{$self->{result}{data}}, $try_line, $try_offset, length $1, 0, 0;
            
            my $catch_pos   = $start + $-[2];
            $line = PLS::Parser::Index->get_line_by_offset($line_offsets, $catch_pos);
            my $catch_line = $line - $previous_line;
            $previous_line = $line;

            my $catch_line_start = $line_offsets->[$line];
            my $catch_offset = $catch_pos - $catch_line_start;

            if ($catch_line == 0)
            {
                $catch_offset -= $previous_pos;
            }

            push @{$self->{result}{data}}, $catch_line, $catch_offset, length $2, 0, 0;

            if (defined $3)
            {
                my $finally_pos = $start + $-[3];
                $line = PLS::Parser::Index->get_line_by_offset($line_offsets, $finally_pos);
                my $finally_line = $line - $previous_line;
                $previous_line = $line;

                my $finally_line_start = $line_offsets->[$line];
                my $finally_offset = $finally_pos - $finally_line_start;

                if ($finally_line == 0)
                {
                    $finally_offset -= $previous_pos;
                }

                push @{$self->{result}{data}}, $finally_line, $finally_offset, length $3, 0, 0;
            }
        }
        elsif ($+{isa} and $+{isa} =~ /\b(isa)\b/)
        {
            if (not $supports_isa)
            {
                next;
            }

            my $isa_pos = $start + $-[1];
            my $line = PLS::Parser::Index->get_line_by_offset($line_offsets, $isa_pos);
            my $isa_line = $line - $previous_line;
            $previous_line = $line;            

            my $isa_line_start = $line_offsets->[$line];
            my $isa_offset = $isa_pos - $isa_line_start;

            if ($isa_line == 0)
            {
                $isa_offset -= $previous_pos;
            }

            push @{$self->{result}{data}}, $isa_line, $isa_offset, length $1, 0, 4;
        }
    } ## end while (${$text} =~ /\b(state|try|catch|defer)|(class)(\s+(?&PerlQualifiedIdentifier))(\s+(?&PerlNumber))?(\s+(?&PerlAttributes))?\b$PPR::GRAMMAR/g...)
    
    use Data::Dumper;

    warn "semantic tokens: " . Dumper($self->{result}{data});
    return $self;
} ## end sub new


1;
