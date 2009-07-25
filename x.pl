my $x = "xxxxxxxx";
substr $x, 2, (length $x) - 2, '...';
warn $x;
