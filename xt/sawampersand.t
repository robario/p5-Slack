#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.1;
use v5.14.0;
use warnings;
use utf8;
use re 0.18 '/amsx';

use CPAN::Meta::Requirements;
use File::Find qw(find);
use Test::More;

BEGIN {
    $ENV{RELEASE_TESTING} or plan( skip_all => 'Test skipped unless environment variable RELEASE_TESTING is set' );
    eval { require Devel::SawAmpersand; } or BAIL_OUT('Failed to load required release-testing module');
    my $requirements = CPAN::Meta::Requirements->from_string_hash(
        {
            'Devel::SawAmpersand' => '== 0.33',
        }
    );
    foreach my $module ( $requirements->required_modules ) {
        if ( not $requirements->accepts_module( $module => $module->VERSION ) ) {
            diag( "$module version mismatch, found " . $module->VERSION );
        }
    }

    Devel::SawAmpersand->import(qw(sawampersand));
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
