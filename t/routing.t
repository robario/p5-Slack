#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Module::Loaded qw(mark_as_loaded);
BEGIN { mark_as_loaded('MyApp::Web'); }

## no critic qw(Modules::ProhibitMultiplePackages)

1;

#
# Here is an example flattened.
#

# lib/MyApp/Web.pm
package MyApp::Web;
use Slack qw(App);

1;

# lib/MyApp/Web/RootExample.pm
package MyApp::Web::RootExample;
use Slack qw(Controller);

sub prefix { return q{/}; }    # prefix '/root-example/' is changed to '/'

action index => q{} => sub {
    res->body('RootExample->index');
};

1;

# lib/MyApp/Web/Hello.pm
package MyApp::Web::Hello;
use Slack qw(Controller);

action index => q{} => sub {
    res->body('Hello->index');
};

action world => sub {
    res->body('hello, world');
};

action name => qr{(?<name>[^/]+)} => sub {
    res->body( sprintf 'Hello, %s!', req->args->{name} );
};

action default => qr/(.+)/ => sub {
    res->body( sprintf 'Hello->default with %s', req->argv->[0] );
};

1;

# lib/MyApp/Web/Hello/World.pm
package MyApp::Web::Hello::World;
use Slack qw(Controller);

action index => q{} => {
    GET => sub {
        res->body('Howdy, World!');
    },
    POST => sub { },
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

package T;
use FindBin qw($Bin);
use HTTP::Request::Common qw(GET POST DELETE);
use HTTP::Status qw(:constants);
use Plack::Test qw(test_psgi);
use Test::More;

sub client {
    my $cb = shift;
    my $res;

    $res = $cb->( GET q{/} );
    is( $res->content, 'RootExample->index', 'index' );    # '/' = '/' + ''

    $res = $cb->( POST q{/} );
    is( $res->code, HTTP_METHOD_NOT_ALLOWED, 'not allowed request method' );

    $res = $cb->( DELETE q{/} );
    is( $res->code, HTTP_NOT_IMPLEMENTED, 'not implemented request method' );

    $res = $cb->( GET '/hello' );
    is( $res->code, HTTP_NOT_FOUND, 'without trailing-slash' );    # '/hello' = '/' + 'hello'

    $res = $cb->( GET '/hello/' );
    is( $res->content, 'Hello->index', 'with trailing-slash' );    # '/hello/' = '/hello/' + ''

    $res = $cb->( GET '/hello/Slack' );
    is( $res->content, 'Hello, Slack!', 'Hello->name matched' );    # '/hello/Slack' = '/hello/' + 'Slack'

    $res = $cb->( GET '/hello/Slack/' );
    is( $res->content, 'Hello->default with Slack/', 'qr/.+/ also matches slash' );    # '/hello/Slack/' = '/hello/' + 'Slack/'

    $res = $cb->( GET '/hello/world' );
    is( $res->content, 'hello, world', 'Hello->world higher priority than Hello->name' );    # '/hello/world' = '/hello/' + 'world'

    $res = $cb->( GET '/hello/world/' );
    is( $res->content, 'Howdy, World!', 'Hello->name does not match' );    # '/hello/world/' = '/hello/world/' + ''

    return;
}
isa_ok( $app, 'MyApp::Web', 'The object' );
test_psgi( $app->to_app, \&client );
done_testing;
