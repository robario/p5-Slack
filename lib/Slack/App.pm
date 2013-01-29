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
    my $self = $class->SUPER::new(
        config => ref $args[0] eq 'HASH' ? $args[0] : {@args},
        controller => [],
    );

    ### Setup Configuration...
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

    $self->config->{Template}->{INCLUDE_PATH} //= $self->config->{rootdir};
    $self->config->{Template}->{ENCODING} //= 'utf8';

    #### config: $self->config

    return $self;
}

sub prefix {
    my ( $self, $prefix ) = @_;
    $prefix = ref $prefix || $prefix;
    ### assert: length $prefix
    my $appname = quotemeta ref $self;
    $prefix =~ s/\A$appname\:://;
    $prefix =~ s/\ARoot//;
    if ($prefix) {
        $prefix =~ s{::}{/}g;
        $prefix = lc $prefix . q{/};
    }
    return $prefix;
}

sub prepare_app {
    my $self = shift;

    ### Setup Controller...
    foreach my $package ( Module::Pluggable::Object->new( search_path => [ ref $self ] )->plugins ) {
        load $package;
        push $self->controller,
          $package->new(
            app    => $self,
            config => $self->config->{$package} // {}
          );
    }

    ### Setup View...
    $self->{view} //= do {
        require Template;
        my $tt = Template->new( $self->config->{Template} );
        sub {
            my ( $context, $req, $res ) = @_;
            my $template = $self->prefix( $context->{controller} ) . $context->{action}->{name} . '.tt';
            $tt->process( $template, $res->stash, \my $output ) or croak $tt->error();
            return $output;
        };
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
    $res->stash( { config => $self->config, req => $req, res => $res } );    # for template
    $context->{action}->{code}->{ $req->method }->( $context, $req, $res );

    if ( !$res->content_type ) {
        $res->content_type('text/html; charset=UTF-8');
    }

    if ( not defined $res->body ) {
        my $output = $self->{view}->( $context, $req, $res );
        $res->body( encode_utf8($output) );
    }

    return $res->finalize;
}

1;
