#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;

use Module::Build;

Module::Build->subclass(
    code => q{
        sub ACTION_manifest_skip {
            my $self = shift;
            $self->SUPER::ACTION_manifest_skip(@_);
            open my $fh, '>>', 'MANIFEST.SKIP' or croak $!;
            print {$fh} <<'EOT';

# Addition
\.ERR$
\.LOG$
\.tdy$
^Slack\.ppd
EOT
            return;
        }
    },
  )->new(
    dist_name    => 'Slack',
    dist_version => '0.01',
    requires     => {
        'HTTP::Status' => 0,
        'Plack'        => 0,
        'Template'     => 0,
    },
    add_to_cleanup => [
        qw(
          *.ERR
          *.LOG
          *.bak
          *.tdy
          *.tmp
          MANIFEST
          MANIFEST.SKIP
          META.json
          META.yml
          Slack-*.tar.gz
          )
    ],
  )->create_build_script;
