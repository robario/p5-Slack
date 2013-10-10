#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.0.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Test::More;

BEGIN {
    eval { require Test::Perl::Critic; Test::Perl::Critic->import; 1; }
      or $ENV{RELEASE_TESTING}
      ? BAIL_OUT('Failed to load required release-testing module')
      : plan( skip_all => 'module not available for testing' );
}

all_critic_ok(qw(lib/ t/ xt/ Build.PL MyModuleBuilder.pm));
