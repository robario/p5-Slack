#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.0.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use re qw(/amsx);
use File::Find qw(find);
use Test::More;

BEGIN {
    eval { require Devel::SawAmpersand; Devel::SawAmpersand->import(qw(sawampersand)); 1; }
      or $ENV{RELEASE_TESTING}
      ? BAIL_OUT('Failed to load required release-testing module')
      : plan( skip_all => 'module not available for testing' );
}

find(
    {
        wanted => sub {
            if (s{\A [.]/lib/ (.+) [.]pm \z}{$1 =~ s{/}{::}gr}e) {
                require_ok($_);
            }
        },
        no_chdir => 1,
    },
    './lib'
);
ok( !sawampersand, 'not sawampersand' );
done_testing;
