#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.2.2;
use v5.14.0;
use warnings;
use encoding::warnings;

use re qw(/amsx);

## no critic qw(Modules::ProhibitMultiplePackages)

package MyApp;
use Carp qw(croak);
use Encode qw(find_encoding);
use FindBin qw($Bin);
use HTTP::Status qw(HTTP_UNSUPPORTED_MEDIA_TYPE);
use JSON::PP;
use Module::Loaded qw(is_loaded);
use Slack qw(App Controller);

BEGIN {
    eval { require Template; Template->import; } or 'do nothing';
}

action default => qr/(?<name>.+)/ => sub {
    res->stash->{name} = req->args->{name};
};

sub html {
    my @args = @_;

    if ( not is_loaded('Template') ) {
        return sub { };
    }

    my $tt = Template->new(
        {
            INCLUDE_PATH => "$Bin/view",
            WRAPPER      => 'wrapper.pc.tt',
            ENCODING     => 'UTF-8',
            @args,
        }
    );
    my $encoder = find_encoding( $tt->service->{WRAPPER}->[0] eq 'wrapper.mobile.tt' ? 'cp932' : 'UTF-8' );

    return sub {
        my $template = c->action->controller->prefix =~ s{\A/}{}r . c->action->name . '.tt';
        $tt->process( $template, { c => c, %{ res->stash } }, \my $output ) or croak $tt->error;
        res->body( $encoder->encode($output) );

        if ( not length res->content_type ) {
            res->content_type('text/html; charset=UTF-8');
        }
    };
}

view mobile => { q{.} => 'mobile' } => html( WRAPPER => 'wrapper.mobile.tt' );

view html => { q{.} => qr/html?/ } => html;

# not equals to { q{/} => 'empty', q{.} => 'json' }
view empty_json => { PATH_INFO => '/empty.json' } => sub {
    res->body('{}');
};

view json => { q{.} => 'json' } => sub {
    state $json = JSON::PP->new->utf8;
    res->body( $json->encode( res->stash ) );
};

view 'never called' => qr/.*[.]json/ => sub {
    croak q{This must not be called because the priority is lower than "q{.}=>'json'".};
};

view plain => { q{.} => 'txt', q{/} => 'foo' } => sub {
    res->body( res->stash->{name} );
};

view unknown => { q{.} => qr/.+/ } => sub {
    res->status(HTTP_UNSUPPORTED_MEDIA_TYPE);
    res->body(q{});
};

view default => html;

package MyApp::Baz;
use Slack qw(Controller);

view 'json override' => { q{.} => 'json' } => sub {
    state $json = JSON::PP->new->utf8->pretty;
    res->body( $json->encode( res->stash ) );
};

package main;
use autodie;
use Encode qw(encode);
use FindBin qw($Bin);
use HTTP::Request::Common qw(GET);
use HTTP::Status qw(HTTP_UNSUPPORTED_MEDIA_TYPE);
use Module::Loaded qw(is_loaded);
use Plack::Test qw(test_psgi);
use Test::More;

sub client {
    my $cb = shift;

  SKIP: {
        if ( not is_loaded('Template') ) {
            skip( 'require Template', 0 );
        }
        my %format;
        foreach my $name (qw(pc mobile)) {
            open my $fh, q{<:encoding(UTF-8)}, "$Bin/view/wrapper.$name.tt";
            $fh->sysread( $format{$name} = q{}, -s $fh );
            $fh->close;
            $format{$name} =~ s/\Q[% content %]\E/%s/;
        }

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
