package Slack::App v0.5.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);
use parent qw(Plack::Component);

use English qw(-no_match_vars);
use HTTP::Status qw(
  is_client_error
  status_message
  HTTP_OK
  HTTP_BAD_REQUEST
  HTTP_NOT_FOUND
  HTTP_METHOD_NOT_ALLOWED
  HTTP_NOT_IMPLEMENTED
  HTTP_INTERNAL_SERVER_ERROR
);
use Module::Load qw(load);
use Module::Pluggable::Object;
use Slack::Context;
use Slack::Request;
use Slack::Response;
use Slack::Util qw(new);

my $CGI_VARIABLES = {
    PATH_INFO      => HTTP_NOT_FOUND,
    REQUEST_METHOD => HTTP_METHOD_NOT_ALLOWED,
};
my %implement;
my $strip;

sub by_clause_priority {
    return
         -( ( $a eq 'PATH_INFO' ) <=> ( $b eq 'PATH_INFO' ) )
      || -( exists $CGI_VARIABLES->{$a} <=> exists $CGI_VARIABLES->{$b} )
      || -( $a =~ /\AHTTP_/ <=> $b =~ /\AHTTP_/ )
      || -( $a =~ /\AX_/ <=> $b =~ /\AX_/ )
      || $a cmp $b;
}

sub prepare_app {
    my $self = shift;

    ### Setup Controller...
    my $class = ref $self;
    my @actions;
    my @strip;
    foreach my $package ( $class, Module::Pluggable::Object->new( search_path => [$class] )->plugins ) {

        # load controller
        if ( not $package->isa('Slack::Controller') ) {
            if ( $package->isa('Slack::App') ) {
                next;
            }
            load $package;
        }

        # define prefix
        if ( not $package->can('prefix') ) {
            my $prefix = $package =~ s/\A\Q$class\E//r;
            if ($prefix) {
                $prefix = join q{/}, map { lc s/(?<=.)\K([[:upper:]])/-$1/gr } split /::/, $prefix;
            }
            $prefix = $prefix . q{/};

            no strict qw(refs);    ## no critic qw(TestingAndDebugging::ProhibitNoStrict)
            *{ $package . '::prefix' } = sub {
                return $prefix;
            };
        }

        # collect actions
        foreach my $action ( $package->actions ) {
            if ( exists $action->clause->{q{.}} ) {
                push @strip, delete $action->clause->{q{.}};
            }
            push @actions, $action;
        }
    }
    ### assert: not grep {$_ eq q{.} or $_ eq q{/}} map {keys $_->clause} @actions
    $strip = join q{|}, @strip;

    # sort and assort actions
    {
        use sort qw(stable);
        my $by_depth = sub {
            return -( $a->controller->prefix =~ tr[/][] <=> $b->controller->prefix =~ tr[/][] );
        };
        $self->{actions}->{prep} = [ sort { -$by_depth->() } grep { $_->type eq 'prep' } @actions ];    # breadth first order
        $self->{actions}->{action} = [ sort $by_depth grep { $_->type eq 'action' } @actions ];         # depth first order
        $self->{actions}->{view}   = [ sort $by_depth grep { $_->type eq 'view' } @actions ];           # ditto
    }
    my $ttt = sub {
        my @table = ( [qw(Controller Name ClauseName ClauseValue)] );
        foreach my $action (@_) {
            my @row;
            foreach my $name ( sort by_clause_priority keys $action->clause ) {
                push @row, [ q{}, q{}, $name, $action->clause->{$name} ];
            }
            ( $row[0]->[0], $row[0]->[1] ) = ( $action->controller, $action->name );
            push @table, @row;
        }
        return rows => \@table, header_row => 1;
    };
    ### prep: $ttt->( @{ $self->{actions}->{prep} } )
    ### action: $ttt->( @{ $self->{actions}->{action} } )
    ### view: $ttt->( @{ $self->{actions}->{view} } )

    foreach my $action ( @{ $self->{actions}->{action} } ) {
        foreach my $method ( keys $action->code ) {
            $implement{$method} = 1;
        }
    }

    # urn:ietf:rfc:2616#5.1.1 The methods GET and HEAD MUST be supported by all general-purpose servers
    # HEAD has been checked by Slack::Controller
    ### assert: exists $implement{GET}

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

    #### Preprocessing...
    foreach my $action ( @{ $self->{actions}->{prep} } ) {
        if ( _process_action( $c, $action ) == HTTP_OK ) {
            ### prep matched: $action->controller . '->' . $action->name
        }
    }

    #### Ensuring response status...
    if ( not $c->res->status ) {
        my $path_info = $c->req->env->{PATH_INFO};
        if ($strip) {
            $c->req->env->{PATH_INFO} =~ s/(?:[.](?:$strip))+\z//;
        }
        foreach my $action ( @{ $self->{actions}->{action} } ) {
            my $r = _process_action( $c, $action );
            if ( $r == HTTP_NOT_FOUND ) {
                next;
            }

            if ( $r == HTTP_OK ) {
                ### action matched: $action->controller . '->' . $action->name
                $c->action($action);
            }

            if ( not $c->res->status ) {
                $c->res->status($r);
            }

            # urn:ietf:rfc:2616#10.4.6
            # The method specified in the Request-Line is not allowed for the resource identified by the Request-URI
            # The response MUST include an Allow header containing a list of valid methods for the requested resource
            if ( $c->res->status == HTTP_METHOD_NOT_ALLOWED ) {
                ## no critic qw(RegularExpressions::ProhibitEnumeratedClasses)
                $c->res->header( Allow => join ', ', grep { /\A[A-Z]+\z/ } keys $action->code );
            }

            last;
        }
        $c->req->env->{PATH_INFO} = $path_info;

        # urn:ietf:rfc:2616#10.4.5 The server has not found anything matching the Request-URI
        if ( not $c->res->status ) {
            $c->res->status(HTTP_NOT_FOUND);
        }
    }

    #### Ensuring response body...
    foreach my $action ( @{ $self->{actions}->{view} } ) {
        if ( defined $c->res->body ) {
            last;
        }
        if ( _process_action( $c, $action ) == HTTP_OK ) {
            ### view matched: $action->controller . '->' . $action->name
        }
    }

    if ( not defined $c->res->body ) {

        # urn:ietf:rfc:2616#10.4 the server SHOULD include an entity containing an explanation of the error situation
        if ( is_client_error( $c->res->status ) ) {
            $c->res->content_type('text/plain; charset=UTF-8');
            $c->res->body( status_message( $c->res->status ) );
        }
        else {
            $c->res->body(q{});
        }
    }

    # urn:ietf:rfc:2616#9.4 the server MUST NOT return a message-body in the response
    if ( $c->req->method eq 'HEAD' ) {    # Plack::Middleware::Head
        $c->res->body(undef);
    }

    return $c->res->finalize;
}

sub _process_action {
    my ( $c, $action ) = @_;
    my %args;
    my @argv;
    foreach my $name ( sort by_clause_priority keys $action->clause ) {
        #### try matching: '[' . $name . '] ' . ( $c->req->env->{$name} // q{} ) . ' =~ ' . $action->clause->{$name}
        if ( exists $c->req->env->{$name} and $c->req->env->{$name} =~ $action->clause->{$name} ) {
            foreach my $i ( 1 .. $#LAST_MATCH_START ) {
                push @argv, substr $c->req->env->{$name}, $LAST_MATCH_START[$i], $LAST_MATCH_END[$i] - $LAST_MATCH_START[$i];
            }
            %args = ( %args, %LAST_PAREN_MATCH );
            next;
        }
        return $CGI_VARIABLES->{$name} // HTTP_BAD_REQUEST;
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
    my $code = $action->code->{$method} // $action->code->{q{*}};
    ### assert: defined $code
    eval {
        if ( my $pre = $action->code->{q{^}} ) {
            $pre->($c);
        }
        $code->($c);
        if ( my $post = $action->code->{q{$}} ) {
            $post->($c);
        }
        1;
    } or return HTTP_INTERNAL_SERVER_ERROR;
    return HTTP_OK;
}

1;
