package Slack::Matcher v0.1.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Class::Struct (
    clause     => q{%},
    code       => q{%},
    controller => 'Slack::Controller',
    name       => q{$},
    type       => q{$},
);

1;
