package Slack v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);
use parent qw(Plack::Component);

use Carp qw(croak);
use Encode qw(encode_utf8);
use Module::Load qw(load);
use Module::Pluggable::Object;
use Plack::Util::Accessor qw(config);
use Slack::Log;
use Slack::Request;
use Slack::Response;
use Slack::Controller ();    # avoid import

sub import {
    my $class = shift;
    foreach (@_) {
        given ($_) {
            when ('Controller') {
                Slack::Controller->import;
            }
            when ('Application') {
                no strict qw(refs);
                push @{ caller . '::ISA' }, __PACKAGE__;
            }
        }
    }
}

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( config => ref $_[0] eq 'HASH' ? $_[0] : {@_} );

    ### Setup Configuration...
    $self->config->{appname}     //= $class;
    $self->config->{environment} //= $ENV{PLACK_ENV};
    $self->config->{appdir}      //= do {
        require Cwd;
        my $pm = $INC{ $class =~ s{::}{/}gr . '.pm' };
        if ($pm) {
            Cwd::abs_path( $pm . '/../../' );
        }
        else {    # for oneliner
            Cwd::getcwd;
        }
    };
    $self->config->{rootdir} //= $self->config->{appdir} . '/root';

    $self->config->{Template}->{INCLUDE_PATH} //= $self->config->{rootdir};
    $self->config->{Template}->{ENCODING} //= 'utf8';

    #### config: $self->config

    return $self;
}

sub prefix {
    my ( $self, $prefix ) = @_;
    ### assert: length $prefix
    my $appname = quotemeta $self->config->{appname};
    $prefix =~ s/\A$appname\:://;
    if ( $prefix !~ s/\ARoot\z// ) {
        $prefix =~ s{::}{/}g;
        $prefix = lc $prefix . '/';
    }
    return $prefix;
}

sub prepare_app {
    my $self = shift;

    ### Setup Controller...
    my $appname = ref $self;
    foreach my $package ( Module::Pluggable::Object->new( search_path => [ $self->config->{appname} ] )->plugins ) {
        load $package;
        $package->new( app => $self );
    }

    ### Setup View...
    $self->{view} //= do {
        require Template;
        my $tt = Template->new( $self->config->{Template} );
        sub {
            my ( $req, $res ) = @_;
            my $template = $self->prefix( ref $req->action->{controller} ) . $req->action->{name} . '.tt';
            $tt->process( $template, $res->stash, \my $output ) or croak $tt->error();
            return $output;
        };
    };

    return;
}

sub call {
    my ( $self, $env ) = @_;

    my $req = Slack::Request->new($env);
    Slack::Controller->find_action($req);
    if ( !$req->action ) {
        return [ 404, [], ['404 Not Found'] ];
    }

    my $res = Slack::Response->new(200);    # TODO: default header
    $res->stash( { config => $self->config, req => $req, res => $res } );
    $req->action->{code}->{ $req->method }->( $req, $res );

    if ( !$res->content_type ) {
        $res->content_type('text/html; charset=UTF-8');
    }

    if ( !$res->body ) {
        my $output = $self->{view}->( $req, $res );
        $res->body( encode_utf8($output) );
    }

    return $res->finalize;
}

1;
