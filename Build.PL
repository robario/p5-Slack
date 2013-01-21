#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;

use Module::Build;

Module::Build->new(
    dist_name    => 'Slack',
    dist_version => '0.01',
    requires     => {
        'Plack'    => 0,
        'Template' => 0,
    },
    add_to_cleanup => [
        qw(
          *.ERR
          *.bak
          *.tdy
          MANIFEST
          MANIFEST.SKIP
          META.json
          META.yml
          Slack-*.tar.gz
          )
    ],
)->create_build_script;
