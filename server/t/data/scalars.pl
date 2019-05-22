my $var = 1; # (0, 3) -> (0, 3)
$var = 2; # (1, 0) -> (0, 3)

sub scalar1 {
    my $var = 3; # (4, 7) -> (4, 7)

    $var = 4; # (6, 4) -> (4, 7)
}

sub scalar2 {
    $var = 5; # (10, 4) -> (0, 3)
}

sub redeclare {
    my $scalar = 1; # (14, 7) -> (14, 7)
    $scalar = 2; # (15, 4) -> (14, 7)
    my $scalar = 3; # (16, 7) -> (16, 7)
    $scalar = 4; # (17, 4) -> (16, 7)
    $scalar = 5; # (18, 4) -> (16, 7)
}
