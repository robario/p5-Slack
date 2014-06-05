#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.1;
use v5.14.0;
use warnings;
use encoding::warnings;
use utf8;
use re 0.18 '/amsx';

use CPAN::Meta::Requirements;
use Test::More;

BEGIN {
    $ENV{RELEASE_TESTING} or plan( skip_all => 'Test skipped unless environment variable RELEASE_TESTING is set' );
    eval { require Test::Strict; } or BAIL_OUT('Failed to load required release-testing module');
    my $requirements = CPAN::Meta::Requirements->from_string_hash(
        {
            'Test::Strict' => '>= 0.22, <= 0.23',
        }
    );
    foreach my $module ( $requirements->required_modules ) {
        if ( not $requirements->accepts_module( $module => $module->VERSION ) ) {
            diag( "$module version mismatch, found " . $module->VERSION );
        }
    }

    package Test::Strict {    ## no critic qw(ProhibitMultiplePackages ProhibitNoWarnings)
        no warnings qw(redefine);

        my $orig = \&modules_enabling_strict;
        *modules_enabling_strict = sub {
            return ( &{$orig}, 'v5.14.0' );
        };
    }

    Test::Strict->import;
}

$Test::Strict::TEST_WARNINGS = 1;
all_perl_files_ok(qw(lib/ t/ xt/ Build.PL MyModuleBuilder.pm));

$Test::Strict::DEVEL_COVER_OPTIONS = '+ignore,"^local/"';
all_cover_ok( 0, qw(t/) );
