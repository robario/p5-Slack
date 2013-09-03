#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.2.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

## no critic qw(Modules::ProhibitMultiplePackages)

package MyApp;
use Carp qw(croak);
use Encode qw(find_encoding);
use FindBin qw($Bin);
use JSON::PP;
use Module::Loaded qw(is_loaded);
use Slack qw(App Controller);

BEGIN {
    eval { require Template; Template->import; } or 'do nothing';
}

action default => qr{(?<name>.+)} => sub {
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

view mobile => { q{.} => qr/mobile/ } => html( WRAPPER => 'wrapper.mobile.tt' );

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
    res->body('This extension is not supported.');
};

view default => qr/.*/ => html;

package MyApp::Baz;
use Slack qw(Controller);

view 'json override' => { q{.} => 'json' } => sub {
    state $json = JSON::PP->new->utf8->pretty;
    res->body( $json->encode( res->stash ) );
};

package T;
use autodie;
use Encode qw(encode);
use FindBin qw($Bin);
use HTTP::Request::Common qw(GET);
use Module::Loaded qw(is_loaded);
use Plack::Test qw(test_psgi);
use Test::More;

sub client {
    my $cb = shift;
    my $res;

  SKIP: {
        if ( not is_loaded('Template') ) {
            skip( 'require Template', 3 );    ## no critic qw(ValuesAndExpressions::ProhibitMagicNumbers)
        }
        my %format;
        foreach my $name (qw(pc mobile)) {
            open my $fh, q{<:encoding(UTF-8)}, "$Bin/view/wrapper.$name.tt";
            $fh->sysread( $format{$name} = q{}, -s $fh );
            $fh->close;
            $format{$name} =~ s/\Q[% content %]\E/%s/;
        }

        $res = $cb->( GET '/foo' );
        is( $res->content, ( sprintf $format{'pc'}, 'foo' ), 'default view' );

        my $unicode = do { use utf8; '日本語'; };
        my %pe = map {
            $_ => do {
                use bytes;
                encode( $_, $unicode ) =~ s/([^\w ])/'%' . ( unpack 'H2', $1 )/egr =~ tr/ /+/r;
              }
        } qw(UTF-8 cp932);

        $res = $cb->( GET sprintf '/%s.mobile', $pe{'UTF-8'} );
        is( $res->content, encode( 'cp932', sprintf $format{'mobile'}, $unicode ), 'mobile view' );
      TODO: {
            local $TODO = 'should guess encoding';
            $res = $cb->( GET sprintf '/%s.mobile', $pe{cp932} );
            is( $res->content, encode( 'cp932', sprintf $format{'mobile'}, $unicode ), 'mobile view' );
        }
    }

    $res = $cb->( GET '/foo.xml' );
    is( $res->content, 'This extension is not supported.', 'no view' );

    $res = $cb->( GET '/foo.json' );
    is( $res->content, '{"name":"foo"}', 'json view' );

    $res = $cb->( GET '/empty.json' );
    is( $res->content, '{}', 'the specific path view' );

    $res = $cb->( GET '/bar/foo.json' );
    is( $res->content, '{"name":"bar/foo"}', 'inherit view' );

    $res = $cb->( GET '/baz/foo.json' );
    is( $res->content, qq{{\n   "name" : "baz/foo"\n}\n}, 'override view' );

    $res = $cb->( GET '/foo.txt' );
    is( $res->content, 'foo', 'plain view matches foo.txt only' );

    $res = $cb->( GET '/bar.txt' );
    like( $res->content, qr/\A\QThis extension is not supported.\E/, 'plain view does not matches except /foo.txt' );

    return;
}

test_psgi( MyApp->new->to_app, \&client );
done_testing;
