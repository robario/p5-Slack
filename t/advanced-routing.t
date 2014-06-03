#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.2.2;
use v5.14.0;
use warnings;
use encoding::warnings;
use utf8;
use re 0.18 '/amsx';

## no critic qw(ProhibitMultiplePackages)

package MyApp::Web;
use Slack qw(App Controller);

prep swallow_begin => sub {
    push @{ res->stash->{callstack} }, 'swallow_begin';
};

view swallow_finish => sub {
    push @{ res->stash->{callstack} }, 'swallow_finish';
    res->header( 'X-CALLSTACK', join q{,}, @{ ( res->stash->{callstack} ) } );
};

package MyApp::Web::Admin;
use Slack qw(Controller);

prep localhost => { REMOTE_ADDR => '127.0.0.1' } => sub {
    push res->stash->{callstack}, 'localhost';
    req->env->{'myapp.authorized'} = 1;
};

prep authorize => { QUERY_STRING => qr/ \b uid=0 \b / } => sub {
    push @{ res->stash->{callstack} }, 'authorize';
    req->env->{'myapp.authorized'} = 1;
};

action admin => { q{/} => q{}, 'myapp.authorized' => 1 } => sub {
    push @{ res->stash->{callstack} }, 'admin';
};

package MyApp::Web::Status;
use Slack qw(Controller);

action 'ignore prefix' => { PATH_INFO => '/ignore-prefix' } => sub { };

action 'POST only' => {
    POST => sub { }
};

action 'bad request' => { q{/} => 'bad request', HTTP_COOKIE => 'bar' } => sub { };

package main;
use HTTP::Request::Common qw(GET POST);
use HTTP::Status qw(:constants);
use Plack::Test qw(test_psgi);
use Test::More;
use Test::Warnings;

sub client {
    my $cb = shift;
    my $res;

    is( $cb->( GET '/ignore-prefix' )->code,        HTTP_OK,        'ignore prefix' );
    is( $cb->( GET '/status/ignore-prefix' )->code, HTTP_NOT_FOUND, 'ignore prefix' );

    is( $cb->( GET '/status/POST only' )->code, HTTP_METHOD_NOT_ALLOWED, '/POST only' );
    is( $cb->( POST '/status/POST only' )->code, HTTP_OK, '/POST only' );

    is( $cb->( GET '/status/bad request' )->code, HTTP_BAD_REQUEST, 'bad request' );
    is( $cb->( GET '/status/bad request', COOKIE => 'bar' )->code, HTTP_OK, 'bad request' );

    $res = $cb->( GET '/foo' );
    is( $res->header('X-CALLSTACK'), 'swallow_begin,swallow_finish', q{} );

    $res = $cb->( GET '/admin/?uid=0' );
    is( $res->header('X-CALLSTACK'), 'swallow_begin,localhost,authorize,admin,swallow_finish', q{} );

    $res = $cb->( GET '/admin/?uid=1' );
    is( $res->header('X-CALLSTACK'), 'swallow_begin,localhost,admin,swallow_finish', q{} );
    return;
}
my $app = MyApp::Web->new;
test_psgi( $app->to_app, \&client );
done_testing;
