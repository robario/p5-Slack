package Slack::Request v0.2.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use parent qw(Plack::Request);

use Plack::Util::Accessor qw(args argv);
use Slack::Util;

sub param {
    my ($self) = @_;
    state $param_for = {
        map { $_ => \&Plack::Request::query_parameters } qw(HEAD GET),
        map { $_ => \&Plack::Request::body_parameters } qw(POST PUT DELETE),
    };

    goto $param_for->{ $self->method };
}

1;
