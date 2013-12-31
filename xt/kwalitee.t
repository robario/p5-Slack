#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Test::More;

BEGIN {
    eval { require Test::Kwalitee; 1; }
      or $ENV{RELEASE_TESTING}
      ? BAIL_OUT('Failed to load required release-testing module')
      : plan( skip_all => 'module not available for testing' );
}

BEGIN {
    use re qw(/amsx);
    use version 0.77;

    require Module::CPANTS::Kwalitee::Uses;
    if ( ( my $v = version->parse( Module::CPANTS::Kwalitee::Uses->VERSION ) ) != ( my $vreq = version->parse('0.92') ) ) {
        diag("Module::CPANTS::Kwalitee::Uses->VERSION == $v != $vreq");
    }
    my $analyse = \&Module::CPANTS::Kwalitee::Uses::analyse;
    no warnings qw(redefine);    ## no critic qw(ProhibitNoWarnings)
    *Module::CPANTS::Kwalitee::Uses::analyse = sub {
        my ( undef, $me ) = @_;
        $analyse->(@_);
        foreach my $module ( @{ $me->d->{modules} } ) {
            foreach my $use ( keys %{ $module->{uses} } ) {
                if ( $use =~ /\Av5[.]/ ) {
                    delete $module->{uses}->{$use};
                    $module->{uses}->{ version->parse($use)->numify } = 1;
                }
            }
        }
    };
}

Test::Kwalitee->import;
