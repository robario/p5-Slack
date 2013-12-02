package Slack::App v0.6.1;
use v5.14.0;
use warnings;
use encoding::warnings;

use parent qw(Plack::Component);
use re qw(/amsx);
use English qw(-no_match_vars);
use HTTP::Status qw(
  is_client_error
  status_message
  HTTP_BAD_REQUEST
  HTTP_METHOD_NOT_ALLOWED
  HTTP_NOT_FOUND
  HTTP_NOT_IMPLEMENTED
  HTTP_OK
);
use Module::Load qw(load);
use Module::Pluggable::Object;
use Slack::Context;
use Slack::Request;
use Slack::Response;
use Slack::Util qw(new);

my $PATH_VARIABLES = {
    q{/}      => HTTP_NOT_FOUND,
    q{.}      => HTTP_NOT_FOUND,
    PATH_INFO => HTTP_NOT_FOUND,
};
my $CGI_VARIABLES = { REQUEST_METHOD => HTTP_METHOD_NOT_ALLOWED };

sub by_clause_priority {
    return
         -( exists $PATH_VARIABLES->{$a} <=> exists $PATH_VARIABLES->{$b} )
      || -( exists $CGI_VARIABLES->{$a} <=> exists $CGI_VARIABLES->{$b} )
      || -( $a =~ /\AHTTP_/ <=> $b =~ /\AHTTP_/ )
      || -( $a =~ /\AX_/ <=> $b =~ /\AX_/ )
      || $a cmp $b;
}

sub prepare_app {
    my $self = shift;

    ### Setup Controller...
    my $class = ref $self;
    $self->{actions} = { prep => [], action => [], view => [] };
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
                $prefix = join q{/}, map { lc s/ (?<=.) (?=\p{PosixUpper}) /-/gr } split /::/, $prefix;
            }
            $prefix = $prefix . q{/};

            no strict qw(refs);    ## no critic qw(ProhibitNoStrict)
            *{ $package . '::prefix' } = sub {
                return $prefix;
            };
        }

        # collect actions
        foreach my $action ( $package->actions ) {
            push $self->{actions}->{ $action->type }, $action;
        }
    }

    # sort and assort actions
    {
        use sort qw(stable);
        my $by_depth = sub {
            return -( $a->controller->prefix =~ tr[/][] <=> $b->controller->prefix =~ tr[/][] );
        };
        $self->{actions}->{prep}   = [ sort { -$by_depth->() } @{ $self->{actions}->{prep} } ];    # breadth first order
        $self->{actions}->{action} = [ sort $by_depth @{ $self->{actions}->{action} } ];           # depth first order
        $self->{actions}->{view}   = [ sort $by_depth @{ $self->{actions}->{view} } ];             # ditto
    }
    my $ttt = sub {
        my @table = ( [qw(Controller Name ClauseName ClauseValue)] );
        foreach my $action (@_) {
            my @row;
            foreach my $name ( sort by_clause_priority keys $action->clause ) {
                push @row, [ q{}, q{}, $name, $action->clause->{$name} ];
            }
            if ( not @row ) {
                push @row, [ q{}, q{}, q{}, q{} ];
            }
            ( $row[0]->[0], $row[0]->[1] ) = ( $action->controller, $action->name );
            push @table, @row;
        }
        return rows => \@table, header_row => 1;
    };
    ### prep: $ttt->( @{ $self->{actions}->{prep} } )
    ### action: $ttt->( @{ $self->{actions}->{action} } )
    ### view: $ttt->( @{ $self->{actions}->{view} } )

    return;
}

sub call {
    my ( $self, $env ) = @_;
    #### $env

    my $c = Slack::Context->new(
        app => $self,
        req => Slack::Request->new($env),
        res => Slack::Response->new(undef),
    );

    state $implement = {
        map { $_ => 1 }
        map { ( $_, $_ eq 'GET' ? ('HEAD') : () ) }
        map { keys $_->code } @{ $self->{actions}->{action} }
    };

    # urn:ietf:rfc:2616#5.1.1 The methods GET and HEAD MUST be supported by all general-purpose servers
    ### assert: exists $implement->{HEAD} and exists $implement->{GET}

    # urn:ietf:rfc:2616#10.5.2 The server does not support the functionality required to fulfill the request
    if ( not exists $implement->{ $c->req->method } ) {
        $c->res->status(HTTP_NOT_IMPLEMENTED);
        return $c->res->finalize;
    }

    ( $c->req->env->{q{/}}, $c->req->env->{q{.}} ) = $c->req->env->{PATH_INFO} =~ /\A([^.]+)(.+)?\z/;

    #### Preprocessing...
    foreach my $action ( @{ $self->{actions}->{prep} } ) {
        if ( _process_action( $c, $action ) == HTTP_OK ) {
            ### prep: $action->controller . '->' . $action->name
        }
    }

    #### Ensuring response status...
    foreach my $action ( @{ $self->{actions}->{action} } ) {
        if ( defined $c->res->status ) {
            last;
        }
        my $r = _process_action( $c, $action );
        if ( $r == HTTP_NOT_FOUND ) {
            next;
        }

        if ( $r == HTTP_OK ) {
            ### action: $action->controller . '->' . $action->name
            $c->action($action);
        }

        if ( not defined $c->res->status ) {
            $c->res->status($r);
        }

        # urn:ietf:rfc:2616#10.4.6
        # The method specified in the Request-Line is not allowed for the resource identified by the Request-URI
        # The response MUST include an Allow header containing a list of valid methods for the requested resource
        if ( $c->res->status == HTTP_METHOD_NOT_ALLOWED ) {
            $c->res->header( Allow => join ', ', grep { /\A \p{PosixUpper}+ \z/ } keys $action->code );
        }
    }

    # urn:ietf:rfc:2616#10.4.5 The server has not found anything matching the Request-URI
    if ( not defined $c->res->status ) {
        $c->res->status(HTTP_NOT_FOUND);
    }

    #### Ensuring response body...
    foreach my $action ( @{ $self->{actions}->{view} } ) {
        if ( defined $c->res->body ) {
            last;
        }
        if ( _process_action( $c, $action ) == HTTP_OK ) {
            ### view: $action->controller . '->' . $action->name
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
    if ( $c->req->method eq 'HEAD' ) {
        $c->res->body(undef);
    }

    return $c->res->finalize;
}

sub _process_action {
    my ( $c, $action ) = @_;
    my %args;
    my @argv;
    foreach my $name ( sort by_clause_priority keys $action->clause ) {
        if ( defined $c->req->env->{$name} ) {
            #### try: sprintf '%s->%s [%s] %s =~ %s', $action->controller, $action->name, $name, $c->req->env->{$name}, $action->clause->{$name}
            if ( $c->req->env->{$name} =~ $action->clause->{$name} ) {
                foreach my $i ( 1 .. $#LAST_MATCH_START ) {
                    push @argv, substr $c->req->env->{$name}, $LAST_MATCH_START[$i], $LAST_MATCH_END[$i] - $LAST_MATCH_START[$i];
                }
                %args = ( %args, %LAST_PAREN_MATCH );
                next;
            }
        }
        return $PATH_VARIABLES->{$name} // $CGI_VARIABLES->{$name} // HTTP_BAD_REQUEST;
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
    if ( my $pre = $action->code->{q{^}} ) {
        $pre->($c);
    }
    $code->($c);
    if ( my $post = $action->code->{q{$}} ) {
        $post->($c);
    }
    return HTTP_OK;
}

1;
