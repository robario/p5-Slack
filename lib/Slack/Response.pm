package Slack::Response v0.2.3;
use v5.14.0;
use warnings;
use utf8;
use re 0.18 '/amsx';

use parent qw(Plack::Response);
use Plack::Util::Accessor qw(stash);
use Slack::Util;

undef *Plack::Response::code;
undef *Plack::Response::content;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->stash( {} );
    return $self;
}

1;
