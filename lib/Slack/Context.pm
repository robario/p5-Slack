package Slack::Context v0.1.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Class::Struct (
    app    => 'Slack::App',
    action => 'Slack::Matcher',
    req    => 'Slack::Request',
    res    => 'Slack::Response',
);

1;
