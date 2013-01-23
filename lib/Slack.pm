package Slack v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;

use Module::Load qw(load);
use Slack::Log;

sub import {
    my $class = shift;

    my $caller = caller;
    foreach my $component ( map { 'Slack::' . $_ } @_ ) {
        load $component;
        $component->import;
        {
            no strict qw(refs);
            push @{ $caller . '::ISA' }, $component;
        }
    }
}

1;
