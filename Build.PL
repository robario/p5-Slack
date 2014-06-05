#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.3.1;
use v5.14.0;
use warnings;
use encoding::warnings;
use utf8;
use re 0.18 '/amsx';

use MyModuleBuilder;

MyModuleBuilder->new(
    module_name        => 'Slack',
    configure_requires => { 'Module::Build' => '0.3800' },
    requires           => { 'Plack' => 0 },
    license            => 'perl',
    create_license     => 1,
    create_readme      => 1,
)->create_build_script;
