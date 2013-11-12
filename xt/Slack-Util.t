#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.0.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use CPAN::Meta::Requirements;
use Test::More;

my $req = CPAN::Meta::Requirements->from_string_hash(
    {
        'Data::Dumper'    => '>= 2.130_02, <= 2.145',
        'Smart::Comments' => '>= 1.000004, <= 1.000005',
    }
);

foreach my $class ( $req->required_modules ) {
    if ( eval "require $class" ) {    ## no critic qw(ProhibitStringyEval)
        ok( $req->accepts_module( $class => $class->VERSION ), "$class-" . $class->VERSION );
    }
    else {
        $ENV{RELEASE_TESTING}
          ? BAIL_OUT('Failed to load required release-testing module')
          : pass('module not available for testing');
    }
}

done_testing;
