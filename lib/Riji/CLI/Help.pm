package Riji::CLI::Help;
use feature ':5.10';
use strict;
use warnings;

sub run {
    my ($class, @argv) = @_;
    say 'First, command `% riji setup` in empty directory.';
}

1;
