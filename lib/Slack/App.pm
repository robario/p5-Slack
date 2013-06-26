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
use Plack::Util::Accessor qw(config actions);
use Slack::Context;
use Slack::Request;
use Slack::Response;
use Slack::Util qw(to_ref);

sub new {
    my ( $class, @args ) = @_;
    if (@args) {
        warnings::warnif( deprecated => '"config" of app is deprecated; please implement your own' );
    }
    return Slack::Util::new(
        $class => {
            config  => to_ref(@args),
            actions => {},
        }
    );
}

my %implement;
my $strip;

sub prepare_app {
    my $self = shift;

    ### Setup Configuration...
    ### config: $self->config

    ### Setup Controller...
    my $package_base_re = ref $self;
    $package_base_re = quotemeta $package_base_re . q{::};
    my @actions;
    my @strip;
    foreach my $package ( Module::Pluggable::Object->new( search_path => [ ref $self ] )->plugins ) {

        # load controller
        if ( not $package->isa('Slack::Controller') ) {
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

        # collect actions
        foreach my $action ( $package->actions ) {
            foreach my $method ( keys $action->code ) {
                $implement{$method} = 1;
            }

            if ( exists $action->clause->{q{.}} ) {
                push @strip, delete $action->clause->{q{.}};
            }
            push @actions, $action;
        }
    }
    $strip = join q{|}, @strip;

    # sort and assort actions
    {
        use sort qw(stable);
        my $by_depth = sub {
            return -( $a->controller->prefix =~ tr[/][] <=> $b->controller->prefix =~ tr[/][] );
        };
        $self->actions->{prep} = [ sort { -$by_depth->() } grep { $_->type eq 'prep' } @actions ];    # breadth first order
        $self->actions->{action} = [ sort $by_depth grep { $_->type eq 'action' } @actions ];         # depth first order
        $self->actions->{view}   = [ sort $by_depth grep { $_->type eq 'view' } @actions ];           # ditto
    }
    ### prep: rows => [ [qw(Controller Name Clause-Key Clause-Value)], map { my $c = $_; my @c = map { [ q{}, q{}, $_, $c->clause->{$_} ] } keys $c->clause; @{ $c[0] }[qw(0 1)] = ( $c->controller, $c->name ); @c } @{ $self->actions->{prep} } ], header_row => 1
    ### action: rows => [ [qw(Controller Name Clause-Key Clause-Value)], map { my $c = $_; my @c = map { [ q{}, q{}, $_, $c->clause->{$_} ] } keys $c->clause; @{ $c[0] }[qw(0 1)] = ( $c->controller, $c->name ); @c } @{ $self->actions->{action} } ], header_row => 1
    ### view: rows => [ [qw(Controller Name Clause-Key Clause-Value)], map { my $c = $_; my @c = map { [ q{}, q{}, $_, $c->clause->{$_} ] } keys $c->clause; @{ $c[0] }[qw(0 1)] = ( $c->controller, $c->name ); @c } @{ $self->actions->{view} } ], header_row => 1

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

    # prep: call all the actions that match
    foreach my $action ( @{ $self->actions->{prep} } ) {
        if ( _process_action( $c, $action ) ) {
            #### prep matched: $action->controller . '->' . $action->name
        }
    }

    # action: call only action that matches the first
    my $path_info = $c->req->env->{PATH_INFO};
    if ($strip) {
        $c->req->env->{PATH_INFO} =~ s/(?:[.](?:$strip))+\z//;
    }
    foreach my $action ( @{ $self->actions->{action} } ) {
        if ( my $r = _process_action( $c, $action ) ) {
            #### action matched: $action->controller . '->' . $action->name
            $c->action($action);

            # urn:ietf:rfc:2616#10.4.6
            # The method specified in the Request-Line is not allowed for the resource identified by the Request-URI
            # The response MUST include an Allow header containing a list of valid methods for the requested resource
            if ( $r == HTTP_METHOD_NOT_ALLOWED ) {
                $c->res->status(HTTP_METHOD_NOT_ALLOWED);
                $c->res->header( Allow => join ', ', keys $c->action->code );
            }

            last;
        }
    }
    $c->req->env->{PATH_INFO} = $path_info;

    # urn:ietf:rfc:2616#10.4.5 The server has not found anything matching the Request-URI
    if ( not $c->action and not $c->res->status ) {
        $c->res->status(HTTP_NOT_FOUND);
    }

    # view: call until body defined
    foreach my $action ( @{ $self->actions->{view} } ) {
        if ( defined $c->res->body ) {
            last;
        }
        if ( _process_action( $c, $action ) ) {
            #### view matched: $action->controller . '->' . $action->name
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

sub _process_action {
    my ( $c, $action ) = @_;
    my %args;
    my @argv;
    foreach my $name ( keys $action->clause ) {
        #### try matching: '[' . $name . '] ' . $c->req->env->{$name} . ' =~ ' . $action->clause->{$name}
        return if not exists $c->req->env->{$name};
        if ( $c->req->env->{$name} =~ $action->clause->{$name} ) {
            foreach my $i ( 1 .. $#LAST_MATCH_START ) {
                push @argv, substr $c->req->env->{$name}, $LAST_MATCH_START[$i], $LAST_MATCH_END[$i] - $LAST_MATCH_START[$i];
            }
            %args = ( %args, %LAST_PAREN_MATCH );
            next;
        }
        return;
    }
    if (@argv) {
        $c->req->argv( \@argv );
        #### argv: $c->req->argv
        if (%args) {
            $c->req->args( \%args );
            #### args: $c->req->args
        }
    }

    # urn:ietf:rfc:2616#9.4 The HEAD method is identical to GET
    my $method = $c->req->method eq 'HEAD' ? 'GET' : $c->req->method;
    my $code = $action->code->{$method};
    if ( not defined $code ) {
        return HTTP_METHOD_NOT_ALLOWED;
    }
    $code->($c);
    return 1;
}

1;
