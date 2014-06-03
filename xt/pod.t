#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use utf8;
use re 0.18 '/amsx';

use CPAN::Meta::Requirements;
use Test::More;

BEGIN {
    $ENV{RELEASE_TESTING} or plan( skip_all => 'Test skipped unless environment variable RELEASE_TESTING is set' );
    eval {
        require Test::Pod;
        require Pod::Simple;
    } or BAIL_OUT('Failed to load required release-testing module');
    my $requirements = CPAN::Meta::Requirements->from_string_hash(
        {
            'Test::Pod'   => '== 1.48',
            'Pod::Simple' => '== 3.28',
        }
    );
    foreach my $module ( $requirements->required_modules ) {
        if ( not $requirements->accepts_module( $module => $module->VERSION ) ) {
            diag( "$module version mismatch, found " . $module->VERSION );
        }
    }

    Test::Pod->import;
}

all_pod_files_ok;
