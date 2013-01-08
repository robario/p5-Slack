#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;

use Module::Build;

Module::Build->new(
    dist_name          => 'Slack',
    dist_version       => 0.01,
    configure_requires => {
        'Module::Build' => 0,
        'perl'          => '5.12.0',
    },
    requires => {
        'Plack'    => 0,
        'Template' => 0,
    },
)->create_build_script;
