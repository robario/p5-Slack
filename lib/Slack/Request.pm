package Slack::Request v0.2.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use parent qw(Plack::Request);

use Plack::Util::Accessor qw(args argv);

my $query_parameters = Plack::Request->can('query_parameters');
my $body_parameters  = Plack::Request->can('body_parameters');
undef *Plack::Request::query_parameters;
undef *Plack::Request::body_parameters;

undef *Plack::Request::param;

sub param {
    my ($self) = @_;
    given ( $self->method ) {
        when ( [qw(HEAD GET)] )        { goto &{$query_parameters} }
        when ( [qw(POST PUT DELETE)] ) { goto &{$body_parameters} }
        default { ... }
    }
    return;
}

1;
