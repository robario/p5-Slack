#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.0.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Test::More;

BEGIN {
    eval { require Test::Strict; Test::Strict->import; 1; }
      or $ENV{RELEASE_TESTING}
      ? BAIL_OUT('Failed to load required release-testing module')
      : plan( skip_all => 'module not available for testing' );
}

BEGIN {
    my $modules_enabling_strict = \&Test::Strict::modules_enabling_strict;
    no warnings qw(redefine);    ## no critic qw(ProhibitNoWarnings)
    *Test::Strict::modules_enabling_strict = sub {
        return ( &{$modules_enabling_strict}, 'v5.14.0' );
    };
}

$Test::Strict::TEST_WARNINGS = 1;
all_perl_files_ok(qw(lib/ t/ xt/ Build.PL MyModuleBuilder.pm));

$Test::Strict::DEVEL_COVER_OPTIONS = '+ignore,"^local/"';
all_cover_ok( 0, qw(t/) );
