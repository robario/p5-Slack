package Slack::App v0.2.0;
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
use Plack::Util::Accessor qw(config action);
use Slack::Request;
use Slack::Response;
use Slack::Util;

sub new {
    my ( $class, @args ) = @_;
    ### Initialize...
    my $self = $class->SUPER::new(
        config => ref $args[0] eq 'HASH' ? $args[0] : {@args},
        action => [],
    );

    $self->config->{appdir} //= do {
        require Cwd;
        my $pm = $class =~ s{::}{/}gr . '.pm';
        if ( $INC{$pm} ) {
            my $dir = Cwd::abs_path( ( $INC{$pm} =~ s/\Q$pm\E\z//r ) . q{..} );
            $dir =~ s{/blib}{}r;
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
    my @action;
    foreach my $package ( Module::Pluggable::Object->new( search_path => [ ref $self ] )->plugins ) {
        if ( not $package->can('new') ) {
            load $package;
        }
        my $appname = ref $self;
        my $prefix = $package . q{/};
        $prefix =~ s/\A\Q$appname\E//;
        $prefix =~ s{::}{/}g;
        $prefix = lc $prefix;
        push @action, $package->new( prefix => $prefix )->action;
    }
    {
        use sort qw(stable);
        push $self->action, reverse sort _by_priority @action;
    }
    ### action: rows => [ [qw(Controller Action Pattern)], map { [ ref $_->{controller}, @$_{qw(name pattern)} ] } @{ $self->action } ], header_row => 1

    ### Setup View...
    $self->{view} //= {
        renderer => do {
            my $renderer = 'Template';
            load $renderer;
            $renderer->new( $self->config->{$renderer} );
        },
        code => sub {
            my ( $self, $action, $req, $res ) = @_;
            if ( not length $res->content_type ) {
                $res->content_type('text/html; charset=UTF-8');
            }
            my $template = $action->{controller}->prefix =~ s{\A/}{}r . $action->{name} . '.tt';
            $self->process( $template, $res->stash, \my $output ) or croak $self->error();
            return $output;
        },
    };

    return;
}

sub call {
    my ( $self, $env ) = @_;

    my $req = Slack::Request->new($env);

    my $path = $req->path;

    my $action;
    foreach my $matcher ( @{ $self->action } ) {
        #### try matching: $path . ' =~ ' . $matcher->{pattern}
        if ( $path !~ $matcher->{pattern} ) {
            next;
        }
        $action = $matcher;
        $req->args( {%LAST_PAREN_MATCH} );
        $req->argv(
            [ map { substr $path, $LAST_MATCH_START[$_], $LAST_MATCH_END[$_] - $LAST_MATCH_START[$_] } 1 .. $#LAST_MATCH_START ] );
        ### matched: rows => [ [ Controller => ref $action->{controller} ], [ Action => $action->{name} ], [ Pattern => $action->{pattern} ], [ Path => $path ], [ '${^MATCH}' => ${^MATCH} ], map { [ '$' . $_, $req->argv->[ $_ - 1 ] ] } 1 .. @{ $req->argv } ]
        last;
    }

    my $res = Slack::Response->new;
    $res->stash->{c} = { app => $self, req => $req };    # for template
    ### assert: not defined $res->status
    ### assert: not defined $res->body
    ### assert: not length $res->content_type

    if ( not $action ) {
        $res->status(HTTP_NOT_FOUND);
        $res->content_type('text/plain; charset=UTF-8');
        $res->body( status_message(HTTP_NOT_FOUND) );
        return $res->finalize;
    }

    my $code = $action->{code}->{ $req->method };
    if ( not $code and $req->method eq 'HEAD' ) {
        $code = $action->{code}->{GET};
    }
    if ( not $code ) {
        $res->status(HTTP_NOT_IMPLEMENTED);
        $res->header( Allow => join ', ', keys $action->{code} );
        return $res->finalize;
    }

    $code->( $action->{controller}, $action, $req, $res );

    if ( not defined $res->body ) {
        my $output = $self->{view}->{code}->( $self->{view}->{renderer}, $action, $req, $res );
        $res->body( encode_utf8( $output // q{} ) );
    }
    if ( $req->method eq 'HEAD' ) {
        $res->body(undef);
    }

    if ( not $res->status ) {
        $res->status(HTTP_OK);
    }

    return $res->finalize;
}

sub _by_priority {
    return $a->{controller}->prefix =~ tr{/}{/} <=> $b->{controller}->prefix =~ tr{/}{/};
}

1;
