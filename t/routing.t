#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.2.1;
use v5.14.0;
use warnings;
use encoding::warnings;

use re qw(/amsx);
use Module::Loaded qw(mark_as_loaded);

BEGIN {
    mark_as_loaded('MyApp::Web');
}

## no critic qw(Modules::ProhibitMultiplePackages)

1;

#
# Here is an example flattened.
#

# lib/MyApp/Web.pm
package MyApp::Web;
use Slack qw(App Controller);

action index => q{} => sub {
    res->body('RootExample->index');
};

1;

# lib/MyApp/Web/Hello.pm
package MyApp::Web::Hello;
use Slack qw(Controller);

action index => q{} => sub {
    res->body('H->index');
};

action world => sub {
    res->body('H->world');
};

action name => qr{(?<name>[^/]+)} => sub {
    res->body( sprintf 'H->name(%s)', req->args->{name} );
};

action default => qr/(.+)/ => sub {
    res->body( sprintf 'H->default(%s)', req->argv->[0] );
};

1;

# lib/MyApp/Web/Hello/World.pm
package MyApp::Web::Hello::World;
use Slack qw(Controller);

action index => q{} => {
    GET => sub {
        res->body('H::W->index');
    },
    POST => sub {    # dummy for implements POST
    },
};

1;

# app.psgi
package main;
use MyApp::Web;
my $app = MyApp::Web->new;

1;

#
# up to here
#

package main;
use FindBin qw($Bin);
use HTTP::Request::Common qw(GET POST DELETE);
use HTTP::Status qw(:constants);
use Plack::Test qw(test_psgi);
use Test::More;

sub client {
    my $cb = shift;
    is( $cb->( GET q{/} )->content, 'RootExample->index',    'index' );               # / = / + ''
    is( $cb->( POST q{/} )->code,   HTTP_METHOD_NOT_ALLOWED, 'not *allowed*' );
    is( $cb->( DELETE q{/} )->code, HTTP_NOT_IMPLEMENTED,    'not *implemented*' );

    is( $cb->( GET '/hello' )->code,     HTTP_NOT_FOUND, 'without trailing-slash' );    # /hello = / + hello
    is( $cb->( GET '/hello/' )->content, 'H->index',     'with trailing-slash' );       # /hello/ = /hello/ + ''

    is( $cb->( GET '/hello/Slack' )->content,  'H->name(Slack)',     'match [^/]+' );        # /hello/Slack = /hello/ + Slack
    is( $cb->( GET '/hello/Slack/' )->content, 'H->default(Slack/)', 'not match [^/]+' );    # /hello/Slack/ = /hello/ + Slack/

    is( $cb->( GET '/hello/world' )->content,  'H->world',    'priority than H->name' );     # /hello/world = /hello/ + world
    is( $cb->( GET '/hello/world/' )->content, 'H::W->index', 'furthermore H->world' );      # /hello/world/ = /hello/world/ + ''
    is( $cb->( GET '/hello/world/foo' )->content, 'H->default(world/foo)', 'uncaught' );    # /hello/world/foo = /hello/ + world/foo

    return;
}
isa_ok( $app, 'MyApp::Web', 'The object' );
test_psgi( $app->to_app, \&client );
done_testing;
