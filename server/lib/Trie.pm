package Node;

sub new
{
    my ($class) = @_;

    my %self = (
                children => {},
                value    => ''
               );

    return bless \%self, $class;
} ## end sub new

sub collect
{
    my ($self, $prefix) = @_;

    my @results;

    if (length $self->{value})
    {
        push @results, (join '', @$prefix);
    }

    foreach my $char (keys %{$self->{children}})
    {
        push @$prefix, $char;
        push @results, @{$self->{children}{$char}->collect($prefix)};
        pop @$prefix;
    } ## end foreach my $char (keys %{$self...})

    return \@results;
} ## end sub collect

package Trie;

sub new
{
    my ($class) = @_;

    my %self = (root => Node->new());

    return bless \%self, $class;
} ## end sub new

sub find
{
    my ($self, $prefix) = @_;

    my @prefix = split //, $prefix;
    my $node   = $self->_get_node(\@prefix);
    return unless (ref $node eq 'Node');
    return $node->collect(\@prefix);
} ## end sub find

sub _get_node
{
    my ($self, $key) = @_;

    my $node = $self->{root};

    foreach my $char (@$key)
    {
        if (ref $node->{children}{$char} eq 'Node')
        {
            $node = $node->{children}{$char};
        }
        else
        {
            return;
        }
    } ## end foreach my $char (@$key)

    return $node;
} ## end sub _get_node

sub find_node
{
    my ($self, $key) = @_;

    my @chars = split //, $key;
    return $self->_get_node(\@chars);
} ## end sub find_node

sub insert
{
    my ($self, $key, $value) = @_;

    my $node = $self->{root};

    foreach my $char (split //, $key)
    {
        if (ref $node->{children}{$char} ne 'Node')
        {
            $node->{children}{$char} = Node->new();
        }

        $node = $node->{children}{$char};
    } ## end foreach my $char (split //,...)

    $node->{value} = $value;
} ## end sub insert

sub delete
{
    my ($self, $key) = @_;

    my @chars     = split //, $key;
    my $last_char = pop @chars;
    my $node      = $self->_get_node(\@chars);
    return unless (ref $node eq 'Node');
    delete $node->{children}{$last_char};
} ## end sub delete

1;
