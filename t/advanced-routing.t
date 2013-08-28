#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

## no critic qw(Modules::ProhibitMultiplePackages)

package MyApp::Web;
use Slack qw(App Controller);

prep swallow_begin => qr/.*/ => sub {
    push @{ res->stash->{callstack} }, 'swallow_begin';
};

view swallow_finish => qr/.*/ => sub {
    push @{ res->stash->{callstack} }, 'swallow_finish';
    res->header( 'X-CALLSTACK', join q{,}, @{ ( res->stash->{callstack} ) } );
};

package MyApp::Web::Admin;
use Slack qw(Controller);

prep localhost => { q{/} => qr/.*/, REMOTE_ADDR => '127.0.0.1' } => sub {
    push res->stash->{callstack}, 'localhost';
    req->env->{'myapp.authorized'} = 1;
};

prep authorize => { q{/} => qr/.*/, QUERY_STRING => qr{\buid=0\b} } => sub {
    push @{ res->stash->{callstack} }, 'authorize';
    req->env->{'myapp.authorized'} = 1;
};

action admin => { q{/} => q{}, 'myapp.authorized' => 1 } => sub {
    push @{ res->stash->{callstack} }, 'admin';
};

package MyApp::Web::Foo;
use Slack qw(Controller);

action 'only have POST action code' => { PATH_INFO => '/only_have_post' } => {
    POST => sub { }
};

action 'only match POST method' => { PATH_INFO => '/only_match_post', REQUEST_METHOD => 'POST' } => sub {
};

package T;
use FindBin qw($Bin);
use HTTP::Request::Common qw(GET);
use HTTP::Status qw(:constants);
use Plack::Test qw(test_psgi);
use Test::More;

sub client {
    my $cb = shift;
    my $res;

    $res = $cb->( GET '/only_have_post' );
    is( $res->code, HTTP_METHOD_NOT_ALLOWED, '/only_have_post only have POST action code' );

    $res = $cb->( GET '/only_match_post' );
    is( $res->code, HTTP_NOT_FOUND, '/only_match_post only match POST method' );

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
