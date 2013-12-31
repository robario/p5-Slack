#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Test::More;

BEGIN {
    eval { require Test::CPAN::Changes; Test::CPAN::Changes->import; 1; }
      or $ENV{RELEASE_TESTING}
      ? BAIL_OUT('Failed to load required release-testing module')
      : plan( skip_all => 'module not available for testing' );
}

changes_ok;
