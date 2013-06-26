package Slack::App v0.3.0;
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
use Slack::Util qw(to_ref);

sub new {
    my ( $class, @args ) = @_;
    return Slack::Util::new(
        $class => {
            config => to_ref(@args),
            action => [],
            view   => [],
        }
    );
}

my %implement;

sub prepare_app {
    my $self = shift;

    ### Setup Configuration...
    ### config: $self->config

    ### Setup Controller...
    my $package_base_re = ref $self;
    $package_base_re = quotemeta $package_base_re . q{::};
    my @action;
    my @view;
    foreach my $package ( Module::Pluggable::Object->new( search_path => [ ref $self ] )->plugins ) {

        # load controller
        if ( not $package->can('new') ) {
            load $package;
        }

        # define prefix
        if ( not $package->can('prefix') ) {
            my $prefix = $package =~ s/\A$package_base_re//r;
            $prefix = join q{/}, map { lc s/(?<=.)\K([[:upper:]])/-$1/gr } split /::/, $prefix;
            $prefix = q{/} . $prefix . q{/};
            no strict qw(refs);    ## no critic qw(TestingAndDebugging::ProhibitNoStrict)
            *{ $package . '::prefix' } = sub {
                return $prefix;
            };
        }

        # collect matchers
        my $controller = $package->new;
        push @action, $controller->action;
        push @view,   $controller->view;
        foreach my $matcher ( @action, @view ) {
            foreach my $method ( keys $matcher->code ) {
                $implement{$method} = 1;
            }
        }
    }
    {
        use sort qw(stable);
        my $by_depth = sub {
            return -( $a->controller->prefix =~ tr[/][] <=> $b->controller->prefix =~ tr[/][] );
        };
        push $self->action, sort $by_depth @action;
        push $self->view,   sort $by_depth @view;
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

    # urn:ietf:rfc:2616#10.5.2 The server does not support the functionality required to fulfill the request
    if ( not exists $implement{ $c->req->method } ) {
        $c->res->status(HTTP_NOT_IMPLEMENTED);
        return $c->res->finalize;
    }

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

    # urn:ietf:rfc:2616#9.4 The HEAD method is identical to GET
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
        # urn:ietf:rfc:2616#10.4.5 The server has not found anything matching the Request-URI
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

    # urn:ietf:rfc:2616#10.4 the server SHOULD include an entity containing an explanation of the error situation
    if ( not defined $c->res->body and is_client_error( $c->res->status ) ) {
        $c->res->content_type('text/plain; charset=UTF-8');
        $c->res->body( status_message( $c->res->status ) );
    }

    # urn:ietf:rfc:2616#9.4 the server MUST NOT return a message-body in the response
    if ( $c->req->method eq 'HEAD' ) {    # Plack::Middleware::Head
        $c->res->body(undef);
    }

    # the default response status code is 200
    if ( not $c->res->status ) {
        $c->res->status(HTTP_OK);
    }

    return $c->res->finalize;
}

1;
