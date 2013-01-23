package Slack v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;

use Module::Load qw(load);
use Slack::Log;

sub import {
    my ( undef, @args ) = @_;

    my $caller = caller;
    foreach my $component ( map { 'Slack::' . $_ } @args ) {
        load $component;
        $component->import;
        {
            no strict qw(refs);    ## no critic (TestingAndDebugging::ProhibitNoStrict)
            push @{ $caller . '::ISA' }, $component;
        }
    }

    return;
}

1;
