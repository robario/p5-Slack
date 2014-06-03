package Slack::Action v0.1.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use utf8;
use re 0.18 '/amsx';

use Class::Struct (
    clause     => q{%},
    code       => q{%},
    controller => 'Slack::Controller',
    name       => q{$},
    type       => q{$},
);

1;
