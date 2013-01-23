package Slack::App v0.0.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);
use parent qw(Plack::Component);

use Carp qw(croak);
use Encode qw(encode_utf8);
use Module::Load qw(load);
use Module::Pluggable::Object;
use Plack::Util::Accessor qw(config controller);
use Slack::Request;
use Slack::Response;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(
        config => ref $_[0] eq 'HASH' ? $_[0] : {@_},
        controller => [],
    );

    ### Setup Configuration...
    $self->config->{environment} //= $ENV{PLACK_ENV};
    $self->config->{appdir} //= do {
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
    my $self = shift;
    my $prefix = ref $_[0] || $_[0];
    ### assert: length $prefix
    my $appname = quotemeta ref $self;
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
                    $req->args( { %+, map { $_ => substr $req->path, $-[$_], $+[$_] - $-[$_] } 1 .. $#- } );
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
        return [ 404, [], ['404 Not Found'] ];
    }

    my $res = Slack::Response->new(200);    # TODO: default header
    $res->stash( { config => $self->config, req => $req, res => $res } );
    $context->{action}->{code}->{ $req->method }->( $context, $req, $res );

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
