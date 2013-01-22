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

my %ACTION;
my %CONTROLLER;

sub import {
    no strict qw(refs);
    my $package = caller;
    foreach (@_) {
        given ($_) {
            when ('Application') {
                push @{ $package . '::ISA' }, 'Slack';
            }
            when ('Controller') {
                Slack::Controller->import;
                push @{ $package . '::ISA' }, 'Slack::Controller';
                *{ $package . '::action' } = sub {
                    push @{ $ACTION{$package} }, \@_;
                };
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
        $CONTROLLER{$package} = $package->new( config => $self->config->{$package} // {} );
        my $prefix = $self->prefix($package);
        $ACTION{$package} = [
            map {
                my ( $pattern, $code ) = @{$_} == 2 ? ( $_->[0], $_->[1] ) : ( $_->[1], $_->[2] );
                given ( ref $pattern ) {
                    when ('') {
                        $pattern = quotemeta $pattern;
                        $pattern = qr/$pattern\z/;
                    }
                    when ('Regexp') { }
                    default         { ... }
                }

                given ( ref $code ) {
                    when ('CODE') { $code = { GET => $code }; }
                    when ('HASH') { }
                    default       { ... }
                }

                [ $_->[0], qr{\A/$prefix$pattern}, $code ];
            } @{ $ACTION{$package} }
        ];
    }

    ### Setup View...
    $self->{view} //= do {
        require Template;
        my $tt = Template->new( $self->config->{Template} );
        sub {
            my ( $context, $req, $res ) = @_;
            my $template = $self->prefix( ref $context->{controller} ) . $context->{action}->[0] . '.tt';
            $tt->process( $template, $res->stash, \my $output ) or croak $tt->error();
            return $output;
        };
    };

    return;
}

sub call {
    my ( $self, $env ) = @_;

    my $req = Slack::Request->new($env);

    my $context = { app => $self };

    my $maxlen = 0;
    foreach my $class ( keys %ACTION ) {
        foreach my $action ( @{ $ACTION{$class} } ) {
            if ( $req->path =~ $action->[1] ) {
                ### match: $req->path . ' matched ' . $action->[1]
                if ( $maxlen <= length ${^MATCH} ) {
                    $maxlen = length ${^MATCH};
                    $req->args( { %+, map { $_ => substr $req->path, $-[$_], $+[$_] - $-[$_] } 1 .. $#- } );
                    $context->{action}     = $action;
                    $context->{controller} = $CONTROLLER{$class};
                }
            }
        }
    }

    if ( !$context->{action} ) {
        return [ 404, [], ['404 Not Found'] ];
    }

    my $res = Slack::Response->new(200);    # TODO: default header
    $res->stash( { config => $self->config, req => $req, res => $res } );
    $context->{action}->[2]->{ $req->method }->( $context, $req, $res );

    if ( !$res->content_type ) {
        $res->content_type('text/html; charset=UTF-8');
    }

    if ( !$res->body ) {
        my $output = $self->{view}->( $context, $req, $res );
        $res->body( encode_utf8($output) );
    }

    return $res->finalize;
}

1;
