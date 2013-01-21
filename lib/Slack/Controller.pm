package Slack::Controller v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Filter::Simple;
use Plack::Component;
use Plack::Util::Accessor qw(app);

my %ACTION;

FILTER_ONLY code => sub {
    s/\breq\b(?!\s*=)/\$_[0]/g;
    s/\bres\b(?!\s*=)/\$_[1]/g;
};

sub import {
    ### assert: $_[0] eq __PACKAGE__
    ### assert: caller eq 'Slack'
    my $package = caller 1;
    no strict qw(refs);
    push @{ $package . '::ISA' }, __PACKAGE__;
    *{ $package . '::action' } = \&action;
}

sub action {
    my $name = shift;

    my $pattern = ( @_ == 2 ) ? shift : $name;
    given ( ref $pattern ) {
        when ('') {
            $pattern = quotemeta $pattern;
            $pattern = qr/$pattern\z/;
        }
        when ('Regexp') { }
        default         { ... }
    }

    my $code = shift;
    given ( ref $code ) {
        when ('CODE') { $code = { GET => $code }; }
        when ('HASH') { }
        default       { ... }
    }

    push @{ $ACTION{ +caller } },
      {
        name    => $name,
        pattern => $pattern,
        code    => $code,
      };
}

sub find_action {
    my ( $class, $req ) = @_;
    my $maxlen = 0;
    foreach my $action ( map { @{$_} } values %ACTION ) {
        if ( $req->path =~ $action->{pattern} ) {
            ### match: $req->path . ' matched ' . $action->{pattern}
            if ( $maxlen <= length ${^MATCH} ) {
                $maxlen = length ${^MATCH};
                $req->action($action);
                $req->args( { %+, map { $_ => substr $req->path, $-[$_], $+[$_] - $-[$_] } 1 .. $#- } );
            }
        }
    }
}

sub new {
    my ($class) = @_;
    my $self = Plack::Component::new(@_);
    foreach my $action ( @{ $ACTION{$class} } ) {
        $action->{controller} = $self;
        my $prefix  = $self->app->prefix($class);
        my $pattern = $action->{pattern};
        $action->{pattern} = qr{\A/$prefix$pattern};
    }
    return $self;
}

sub config {
    my $self = shift;
    return $self->app->config->{ ref $self };
}

1;
