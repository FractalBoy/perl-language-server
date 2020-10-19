package PLS::Parser::BuiltIns;

use strict;
use warnings;

use File::Spec;
use IPC::Open3;
use Pod::Markdown;
use Symbol 'gensym';

sub get_builtin_function_documentation
{
    my ($function, $markdown) = @_;

    return run_perldoc_command($markdown, '-Tuf', $function);
}

sub get_builtin_variable_documentation
{
    my ($variable, $markdown) = @_;

    return run_perldoc_command($markdown, '-Tuv', $variable);
}

sub run_perldoc_command
{
    my ($markdown, @command) = @_;

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, get_perldoc_location(), @command);

    close $in, () = <$err>; # need to read all of error file handle
    my $pod = do { local $/; <$out> };
    close $out;
    waitpid $pid, 0;
    my $exit_code = $? >> 8;
    return 0 if $exit_code != 0;

    my $parser = Pod::Markdown->new();
    $parser->output_string($markdown);
    $parser->parse_string_document($pod);

    # remove first extra space to avoid markdown from being displayed inappropriately as code
    $$markdown =~ s/\n\n/\n/;

    return 1;
}

sub get_perldoc_location
{
    my (undef, $dir) = File::Spec->splitpath($^X);
    my $perldoc = File::Spec->catfile($dir, 'perldoc');
    # try to use the perldoc matching this perl executable, falling back to the perldoc in the PATH
    return (-f $perldoc and -x $perldoc) ? $perldoc : 'perldoc';
}

1;
