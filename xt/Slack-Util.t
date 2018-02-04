#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.1;
use v5.14.0;
use warnings;
use utf8;
use re 0.18 '/amsx';

use CPAN::Meta::Requirements;
use Test::More;

BEGIN {
    $ENV{RELEASE_TESTING} or plan( skip_all => 'Test skipped unless environment variable RELEASE_TESTING is set' );
    eval {
        require Data::Dumper;
        require Smart::Comments;
    } or BAIL_OUT('Failed to load required release-testing module');
    my $requirements = CPAN::Meta::Requirements->from_string_hash(
        {
            'Data::Dumper'    => '>= 2.130_02, <= 2.145',
            'Smart::Comments' => '>= 1.000004, <= 1.000005',
        }
    );
    foreach my $module ( $requirements->required_modules ) {
        ok( $requirements->accepts_module( $module => $module->VERSION ), "$module version mismatch, found " . $module->VERSION );
    }
}

done_testing;
