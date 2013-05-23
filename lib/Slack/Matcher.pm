package Slack::Matcher v0.0.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Class::Struct (
    code       => q{%},
    controller => 'Slack::Controller',
    extension  => q{$},
    name       => q{$},
    pattern    => q{$},
);

1;
