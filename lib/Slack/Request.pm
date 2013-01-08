package Slack::Request v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use parent qw(Plack::Request);

use Plack::Util::Accessor qw(action args);

my $query_parameters = Plack::Request->can('query_parameters');
my $body_parameters  = Plack::Request->can('body_parameters');
undef *Plack::Request::query_parameters;
undef *Plack::Request::body_parameters;

undef *Plack::Request::param;

sub param {
    given ( $_[0]->method ) {
        when ( [qw(HEAD GET)] )        { goto &{$query_parameters} }
        when ( [qw(POST PUT DELETE)] ) { goto &{$body_parameters} }
        default { ... }
    }
}

1;
