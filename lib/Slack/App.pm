package Slack::App v0.2.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);
use parent qw(Plack::Component);

use English qw(-no_match_vars);
use HTTP::Status qw(:constants status_message is_client_error);
use Module::Load qw(load);
use Module::Pluggable::Object;
use Plack::Util::Accessor qw(config action view);
use Slack::Context;
use Slack::Request;
use Slack::Response;
use Slack::Util;

sub _by_priority {
    return -( $a->priority <=> $b->priority );
}

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
        ( my $prefix = $package ) =~ s/\A\Q$appname\E:://;
        $prefix = join q{/}, map { lc s/(?<=.)\K([[:upper:]])/-$1/gr } split /::/, $prefix;
        $prefix = q{/} . $prefix . q{/};
        my $controller = $package->new( prefix => $prefix );
        push @action, $controller->action;
        push @view,   $controller->view;
    }
    {
        use sort qw(stable);

        push $self->action, sort _by_priority @action;
        push $self->view,   sort _by_priority @view;
    }
    ### action: rows => [ [qw(Controller Name Pattern)], map { [ ref $_->controller, $_->name, $_->pattern ] } @{ $self->action } ], header_row => 1
    ### view: rows => [ [qw(Controller Name Pattern)], map { [ ref $_->controller, $_->name, $_->pattern ] } @{ $self->view } ], header_row => 1

    return;
}

sub call {
    my ( $self, $env ) = @_;

    my $c = Slack::Context->new(
        app => $self,
        req => Slack::Request->new($env),
        res => Slack::Response->new(0),
    );

    my $path = $c->req->path;

    foreach my $matcher ( @{ $self->view } ) {
        #### view try matching: $path . ' =~ ' . $matcher->pattern
        if ( not $path =~ $matcher->pattern ) {
            next;
        }
        #### view matched: rows => [ [ Controller => ref $matcher->controller ], [ Name => $matcher->name ], [ Pattern => $matcher->pattern ], [ Path => $path ], [ q{$} . '{^MATCH}' => ${^MATCH} ] ]
        $c->view($matcher);
        if ( length $c->view->extension ) {
            $path =~ s/[.]@{[$c->view->extension]}\z//;
        }
        last;
    }

    foreach my $matcher ( @{ $self->action } ) {
        #### action try matching: $path . ' =~ ' . $matcher->pattern
        if ( not $path =~ $matcher->pattern ) {
            next;
        }
        $c->req->args( {%LAST_PAREN_MATCH} );
        $c->req->argv(
            [ map { substr $path, $LAST_MATCH_START[$_], $LAST_MATCH_END[$_] - $LAST_MATCH_START[$_] } 1 .. $#LAST_MATCH_START ] );
        #### action matched: rows => [ [ Controller => ref $matcher->controller ], [ Name => $matcher->name ], [ Pattern => $matcher->pattern ], [ Path => $path ], [ q{$} . '{^MATCH}' => ${^MATCH} ], map { [ q{$} . $_, $c->req->argv->[ $_ - 1 ] ] } 1 .. @{ $c->req->argv } ]
        $c->action($matcher);
        last;
    }

    # urn:ietf:rfc:2616#9.4: The HEAD method is identical to GET
    my $method = $c->req->method eq 'HEAD' ? 'GET' : $c->req->method;

    if ( $c->action ) {
        my $code = $c->action->code->{$method};
        if ($code) {
            #### Process action...
            $code->($c);
        }
        else {
            # urn:ietf:rfc:2616#10.4.6
            # The method specified in the Request-Line is not allowed for the resource identified by the Request-URI
            # The response MUST include an Allow header containing a list of valid methods for the requested resource
            $c->res->status(HTTP_METHOD_NOT_ALLOWED);
            $c->res->header( Allow => join ', ', keys $c->action->code );
        }
    }
    else {
        # urn:ietf:rfc:2616#10.4.5: The server has not found anything matching the Request-URI
        $c->res->status(HTTP_NOT_FOUND);
    }

    if ( not defined $c->res->body ) {
        if ( $c->view ) {
            my $code = $c->view->code->{$method} // $c->view->code->{GET};
            #### Process view...
            $code->($c);
        }
        else {
            $c->res->body(q{});
        }
    }

    #### Fixup response...

    # urn:ietf:rfc:2616#10.4: the server SHOULD include an entity containing an explanation of the error situation
    if ( not defined $c->res->body and is_client_error( $c->res->status ) ) {
        $c->res->content_type('text/plain; charset=UTF-8');
        $c->res->body( status_message( $c->res->status ) );
    }

    # urn:ietf:rfc:2616#9.4: the server MUST NOT return a message-body in the response
    if ( $c->req->method eq 'HEAD' ) {
        $c->res->body(undef);
    }

    # the default response status code is 200
    if ( not $c->res->status ) {
        $c->res->status(HTTP_OK);
    }

    return $c->res->finalize;
}

1;
