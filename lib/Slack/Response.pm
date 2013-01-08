package Slack::Response v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use parent qw(Plack::Response);

use Plack::Util::Accessor qw(param stash);

undef *Plack::Response::code;
undef *Plack::Response::content;

1;
