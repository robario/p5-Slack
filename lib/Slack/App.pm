package Slack::App v0.1.1;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);
use parent qw(Plack::Component);

use Carp qw(croak);
use Encode qw(encode_utf8);
use English qw(-no_match_vars);
use HTTP::Status qw(:constants status_message);
use Module::Load qw(load);
use Module::Pluggable::Object;
use Plack::Util::Accessor qw(config controller);
use Slack::Request;
use Slack::Response;
use Slack::Util;

sub import {
    Slack::Util->import;
    return;
}

sub new {
    my ( $class, @args ) = @_;
    ### Initialize...
    my $self = $class->SUPER::new(
        config => ref $args[0] eq 'HASH' ? $args[0] : {@args},
        controller => [],
    );

    $self->config->{environment} //= $ENV{PLACK_ENV};
    $self->config->{appdir} //= do {
        require Cwd;
        my $pm = $class =~ s{::}{/}gr . '.pm';
        if ( $INC{$pm} ) {
            Cwd::abs_path( ( $INC{$pm} =~ s/\Q$pm\E\z//r ) . q{..} );
        }
        else {    # for oneliner
            Cwd::getcwd;
        }
    };
    $self->config->{rootdir} //= $self->config->{appdir} . '/root';

    return $self;
}

sub prepare_app {
    my $self = shift;

    ### Setup Configuration...
    $self->config->{Template}->{INCLUDE_PATH} //= $self->config->{rootdir};
    $self->config->{Template}->{ENCODING} //= 'utf8';
    ### config: $self->config

    ### Setup Controller...
    foreach my $package ( Module::Pluggable::Object->new( search_path => [ ref $self ] )->plugins ) {
        load $package;
        push $self->controller, $package->new( app => $self );
    }

    ### Setup View...
    $self->{view} //= {
        renderer => do {
            my $renderer = 'Template';
            load $renderer;
            $renderer->new( $self->config->{$renderer} );
        },
        code => sub {
            my ( $self, $controller, $action, $req, $res ) = @_;
            my $template = $controller->prefix =~ s{\A/}{}r . $action->{name} . '.tt';
            $self->process( $template, $res->stash, \my $output ) or croak $self->error();
            return $output;
        },
    };

    return;
}

sub call {
    my ( $self, $env ) = @_;

    my $req = Slack::Request->new($env);
    my $context;

    my $maxlen = 0;
    foreach my $controller ( @{ $self->controller } ) {
        foreach my $action ( @{ $controller->action } ) {
            if ( $req->path =~ $action->{pattern} ) {
                ### match: $req->path . ' matched ' . $action->{pattern}
                if ( $maxlen <= length ${^MATCH} ) {
                    $maxlen = length ${^MATCH};
                    $req->args( {%LAST_PAREN_MATCH} );
                    $req->argv(
                        [
                            map { substr $req->path, $LAST_MATCH_START[$_], $LAST_MATCH_END[$_] - $LAST_MATCH_START[$_] }
                              1 .. $#LAST_MATCH_START
                        ]
                    );

                    $context = {
                        app        => $self,
                        action     => $action,
                        controller => $controller,
                    };
                }
            }
        }
    }

    if ( !$context ) {
        return [ HTTP_NOT_FOUND, [], [ status_message(HTTP_NOT_FOUND) ] ];
    }

    my $res = Slack::Response->new(HTTP_OK);    # TODO: default header
    $res->stash( { c => $context, req => $req, res => $res } );    # for template
    $context->{action}->{code}->{ $req->method }->( $context, $req, $res );

    if ( !$res->content_type ) {
        $res->content_type('text/html; charset=UTF-8');
    }

    if ( not defined $res->body ) {
        my $output = $self->{view}->{code}->( $self->{view}->{renderer}, $context->{controller}, $context->{action}, $req, $res );
        $res->body( encode_utf8($output) );
    }

    return $res->finalize;
}

1;
