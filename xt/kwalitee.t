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
    eval {
        require Test::Kwalitee;
        require Module::CPANTS::Kwalitee::Uses;
    } or BAIL_OUT('Failed to load required release-testing module');
    my $requirements = CPAN::Meta::Requirements->from_string_hash(
        {
            'Test::Kwalitee'                 => '== 1.18',
            'Module::CPANTS::Kwalitee::Uses' => '== 0.92',
        }
    );
    foreach my $module ( $requirements->required_modules ) {
        if ( not $requirements->accepts_module( $module => $module->VERSION ) ) {
            diag( "$module version mismatch, found " . $module->VERSION );
        }
    }

    package Module::CPANTS::Kwalitee::Uses {    ## no critic qw(ProhibitMultiplePackages ProhibitNoWarnings)
        no warnings qw(redefine);

        use version 0.77;

        my $orig = \&analyse;
        *analyse = sub {
            my ( undef, $me ) = @_;
            $orig->(@_);
            foreach my $module ( @{ $me->d->{modules} } ) {
                foreach my $use ( keys %{ $module->{uses} } ) {
                    if ( $use =~ /\Av5[.] / ) {
                        delete $module->{uses}->{$use};
                        $module->{uses}->{ version->parse($use)->numify } = 1;
                    }
                }
            }
        };
    }
}

Test::Kwalitee->import;
