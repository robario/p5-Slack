package Slack::Context v0.3.1;
use v5.14.0;
use warnings;
use utf8;
use re 0.18 '/amsx';

use Class::Struct (
    app    => 'Slack::App',
    action => 'Slack::Action',
    req    => 'Slack::Request',
    res    => 'Slack::Response',
);

sub c {
    return shift;
}

1;
