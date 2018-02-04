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
        require Perl::Critic;
        require Test::Perl::Critic;
    } or BAIL_OUT('Failed to load required release-testing module');
    my $requirements = CPAN::Meta::Requirements->from_string_hash(
        {
            'Test::Perl::Critic' => '== 1.02',
            'Perl::Critic'       => '== 1.121',
        }
    );
    foreach my $module ( $requirements->required_modules ) {
        if ( not $requirements->accepts_module( $module => $module->VERSION ) ) {
            diag( "$module version mismatch, found " . $module->VERSION );
        }
    }

    Test::Perl::Critic->import;
}

all_critic_ok(qw(lib/ t/ xt/ Build.PL MyModuleBuilder.pm));
