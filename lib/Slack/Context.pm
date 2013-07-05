package Slack::Context v0.2.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Class::Struct (
    app    => 'Slack::App',
    action => 'Slack::Action',
    req    => 'Slack::Request',
    res    => 'Slack::Response',
);

1;
