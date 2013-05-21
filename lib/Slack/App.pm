package Slack::App v0.2.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);
use parent qw(Plack::Component);

use English qw(-no_match_vars);
use HTTP::Status qw(:constants status_message);
use Module::Load qw(load);
use Module::Pluggable::Object;
use Plack::Util::Accessor qw(config action view);
use Slack::Request;
use Slack::Response;
use Slack::Util;

sub new {
    my ( $class, @args ) = @_;
    ### Initialize...
    my $self = $class->SUPER::new(
        config => ref $args[0] eq 'HASH' ? $args[0] : {@args},
        action => [],
        view   => [],
    );

    $self->config->{appdir} //= do {
        require Cwd;
        my $pm = $class =~ s{::}{/}gr . '.pm';
        if ( $INC{$pm} ) {
            my $dir = $INC{$pm};
            if ( $dir =~ s/\Q$pm\E\z// ) {
                $dir .= q{..};
            }
            else {
                # non-standard directory structure
                $dir =~ s{[^/]+\z}{};
            }
            $dir = Cwd::abs_path($dir);
            $dir =~ s{/blib}{};
            $dir;
        }
        else {
            # for one-liner
            Cwd::getcwd;
        }
    };
    $self->config->{rootdir} //= $self->config->{appdir} . '/root';

    return $self;
}

sub prepare_app {
    my $self = shift;

    ### Setup Configuration...
    ### config: $self->config

    ### Setup Controller...
    my @action;
    my @view;
    foreach my $package ( Module::Pluggable::Object->new( search_path => [ ref $self ] )->plugins ) {
        if ( not $package->can('new') ) {
            load $package;
        }

        my $appname = ref $self;
        my $prefix  = $package . q{/};
        $prefix =~ s/\A\Q$appname\E//;
        $prefix =~ s{::}{/}g;
        $prefix = lc $prefix;
        my $controller = $package->new( prefix => $prefix );
        push @action, $controller->action;
        push @view,   $controller->view;
    }
    {
        use sort qw(stable);
        push $self->action, reverse sort _by_priority @action;
        push $self->view,   reverse sort _by_priority @view;
    }
    ### action: rows => [ [qw(Controller Name Pattern)], map { [ ref $_->{controller}, @$_{qw(name pattern)} ] } @{ $self->action } ], header_row => 1
    ### view: rows => [ [qw(Controller Name Pattern)], map { [ ref $_->{controller}, @$_{qw(name pattern)} ] } @{ $self->view } ], header_row => 1

    return;
}

sub call {
    my ( $self, $env ) = @_;

    my $req = Slack::Request->new($env);

    my $path = $req->path;

    my $view;
    foreach my $matcher ( @{ $self->view } ) {
        #### view try matching: $path . ' =~ ' . $matcher->{pattern}
        if ( $path !~ $matcher->{pattern} ) {
            next;
        }
        ### view matched: rows => [ [ Controller => ref $matcher->{controller} ], [ Name => $matcher->{name} ], [ Pattern => $matcher->{pattern} ], [ Path => $path ], [ '${^MATCH}' => ${^MATCH} ] ]
        $view = $matcher;
        if ( length $view->{extension} ) {
            $path =~ s/[.]$view->{extension}\z//;
        }
        last;
    }

    my $action;
    foreach my $matcher ( @{ $self->action } ) {
        #### action try matching: $path . ' =~ ' . $matcher->{pattern}
        if ( $path !~ $matcher->{pattern} ) {
            next;
        }
        $req->args( {%LAST_PAREN_MATCH} );
        $req->argv(
            [ map { substr $path, $LAST_MATCH_START[$_], $LAST_MATCH_END[$_] - $LAST_MATCH_START[$_] } 1 .. $#LAST_MATCH_START ] );
        ### action matched: rows => [ [ Controller => ref $matcher->{controller} ], [ Name => $matcher->{name} ], [ Pattern => $matcher->{pattern} ], [ Path => $path ], [ '${^MATCH}' => ${^MATCH} ], map { [ '$' . $_, $req->argv->[ $_ - 1 ] ] } 1 .. @{ $req->argv } ]
        $action = $matcher;
        last;
    }

    my $res = Slack::Response->new;
    ### assert: not defined $res->status
    ### assert: not defined $res->body
    ### assert: not length $res->content_type

    if ($action) {
        ### Process action...
        my $code = $action->{code}->{ $req->method };
        if ( not $code and $req->method eq 'HEAD' ) {
            $code = $action->{code}->{GET};
        }
        if ( not $code ) {
            $res->status(HTTP_NOT_IMPLEMENTED);
            $res->header( Allow => join ', ', keys $action->{code} );
            return $res->finalize;
        }
        $code->( $self, $action, $view, $req, $res );
    }
    else {
        $res->status(HTTP_NOT_FOUND);
        $res->content_type('text/plain; charset=UTF-8');
        $res->body( status_message(HTTP_NOT_FOUND) );
        return $res->finalize;
    }

    if ( not defined $res->body ) {
        if ($view) {
            ### Process view...
            my $code = $view->{code}->{ $req->method } // $view->{code}->{GET};
            $code->( $self, $action, $view, $req, $res );
        }
        else {
            $res->body(q{});
        }
    }

    ### Fixup response...
    if ( $req->method eq 'HEAD' ) {
        $res->body(undef);
    }

    if ( not $res->status ) {
        $res->status(HTTP_OK);
    }

    return $res->finalize;
}

sub _by_priority {
    return $a->{controller}->prefix =~ tr{/}{/} <=> $b->{controller}->prefix =~ tr{/}{/}
      or length $a->{extension} ? 1 : 0 <=> length $b->{extension} ? 1 : 0;
}

1;
