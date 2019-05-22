sub subroutine; # (0, 4) -> (15, 8)

subroutine; # (2, 0) -> (15, 8)

sub subroutine { # (4, 4) -> (15, 8)
    ...
}

subroutine2; # (8, 0) -> undef
subroutine2(); # (9, 0) -> (13, 4)
&subroutine2; # (10, 0) -> (13, 4)
subroutine; # (11, 0) -> (15, 8)

sub subroutine2 { # (13, 4) -> (13, 4)
    subroutine; # (14, 4) -> (15, 8)
    sub subroutine { # (15, 8) -> (15, 8)
        ...
    }
}

subroutine2; # (20, 0) -> (13, 4)
subroutine; # (21, 0) -> (15, 8)
