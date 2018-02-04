#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.2.4;
use v5.14.0;
use warnings;
use utf8;
use re 0.18 '/amsx';

my %format = (
    pc     => "<!DOCTYPE html>\n<title>%s</title>",
    mobile => '<html><head><meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS"><title>%s</title></head></html>',
);

## no critic qw(ProhibitMultiplePackages)

package MyApp;
use Carp qw(croak);
use Encode qw(find_encoding);
use HTTP::Status qw(:constants);
use JSON::PP;
use Slack qw(App Controller);

action default => qr/(?<name>.+)/ => sub {
    res->stash->{name} = req->args->{name};
};

sub html {
    my ($format) = @_;
    my $encoder = find_encoding( $format eq 'mobile' ? 'cp932' : 'UTF-8' );
    my %template = ( default => '[% name %]' );

    return sub {
        my $output = sprintf $format{$format}, $template{ c->action->name } =~ s/ \Q[%\E \s* (\S+) \s* \Q%]\E /res->stash->{$1}/egr;
        res->body( $encoder->encode($output) );
        if ( not length res->content_type ) {
            res->content_type('text/html; charset=UTF-8');
        }
    };
}

view mobile => { q{.} => 'mobile' } => html('mobile');

view html => { q{.} => qr/html?/ } => html('pc');

# not equals to { q{/} => 'empty', q{.} => 'json' }
view empty_json => { PATH_INFO => '/empty.json' } => sub {
    res->body('{}');
};

view json => { q{.} => 'json' } => sub {
    state $json = JSON::PP->new->utf8;
    res->body( $json->encode( res->stash ) );
};

view 'never called' => qr/.*[.]json/ => sub {
    croak(q{This must not be called because the priority is lower than "q{.}=>'json'".});
};

view plain => { q{.} => 'txt', q{/} => 'foo' } => sub {
    res->body( res->stash->{name} );
};

view unknown => { q{.} => qr/.+/ } => sub {
    res->status(HTTP_UNSUPPORTED_MEDIA_TYPE);
    res->body(q{});
};

view default => html('pc');

package MyApp::Baz;
use JSON::PP;
use Slack qw(Controller);

view 'json override' => { q{.} => 'json' } => sub {
    state $json = JSON::PP->new->utf8->pretty;
    res->body( $json->encode( res->stash ) );
};

package main;
use Encode qw(encode);
use HTTP::Request::Common qw(GET);
use HTTP::Status qw(:constants);
use Plack::Test qw(test_psgi);
use Test::More;
use Test::Warnings;

sub client {
    my $cb = shift;

    is( $cb->( GET '/foo' )->content, ( sprintf $format{'pc'}, 'foo' ), 'default view' );

    my $unicode = do { use utf8; '日本語'; };
    my %pe = map {
        $_ => do {
            use bytes;
            encode( $_, $unicode ) =~ s/([^\w ])/'%' . ( unpack 'H2', $1 )/egr =~ tr/ /+/r;
          }
    } qw(UTF-8 cp932);

    is(
        $cb->( GET sprintf '/%s.mobile', $pe{'UTF-8'} )->content,
        encode( 'cp932', sprintf $format{'mobile'}, $unicode ),
        'mobile view'
    );
  TODO: {
        local $TODO = 'should guess encoding';
        is(
            $cb->( GET sprintf '/%s.mobile', $pe{cp932} )->content,
            encode( 'cp932', sprintf $format{'mobile'}, $unicode ),
            'mobile view'
        );
    }

    is( $cb->( GET '/foo.xml' )->code,         HTTP_UNSUPPORTED_MEDIA_TYPE,       'no view' );
    is( $cb->( GET '/foo.json' )->content,     '{"name":"foo"}',                  'json view' );
    is( $cb->( GET '/empty.json' )->content,   '{}',                              'the specific path view' );
    is( $cb->( GET '/bar/foo.json' )->content, '{"name":"bar/foo"}',              'inherit view' );
    is( $cb->( GET '/baz/foo.json' )->content, qq{{\n   "name" : "baz/foo"\n}\n}, 'override view' );
    is( $cb->( GET '/foo.txt' )->content,      'foo',                             'plain view matches foo.txt only' );
    is( $cb->( GET '/bar.txt' )->code,         HTTP_UNSUPPORTED_MEDIA_TYPE,       'plain view does not matches except /foo.txt' );
    return;
}

test_psgi( MyApp->new->to_app, \&client );
done_testing;
