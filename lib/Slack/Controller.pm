package Slack::Controller v0.3.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Filter::Simple;
use Plack::Component;
use Slack::Util;

FILTER_ONLY code => sub {
    my %replacement = (
        ## no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)
        req => '$_[2]',
        res => '$_[3]',
    );
    while ( my ( $keyword, $replacement ) = each %replacement ) {
        s/(?<![\$@%&*])$keyword\b(?!\s*=>)/$replacement/g;
    }
};

sub import {
    ### assert: caller eq 'Slack'
    my $package = caller 1;
    my $action  = sub {
        state @action;
        if ( $_[0]->isa(__PACKAGE__) ) {    # call as method
            shift;
            if (@_) {
                @action = @_;
            }
        }
        else {                              # call as subroutine
            ### assert: @_ == 2 or @_ == 3
            push @action, \@_;
        }
        return @action;
    };
    {
        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict qw(refs);
        *{ $package . '::action' } = $action;
    }
    return;
}

sub new {
    my ( $class, %option ) = @_;
    ### assert: $class ne __PACKAGE__
    my $self = Plack::Component::new( $class, %option );

    # reconstruct actions
    my @action;
    my $prefix = $self->prefix;
    ### assert: $prefix =~ qr{\A/}
    foreach my $action ( $self->action ) {
        my $name    = $action->[0];
        my $pattern = @{$action} == 2 ? $name : $action->[1];
        my $code    = @{$action} == 2 ? $action->[1] : $action->[2];

        given ( ref $pattern ) {
            when (q{}) {
                $pattern = qr{\A$prefix\Q$pattern\E\z}p;
            }
            when ('Regexp') {
                $pattern = qr{\A$prefix$pattern}p;
            }
            default { ... }
        }

        given ( ref $code ) {
            when ('CODE') { $code = { GET => $code }; }
            when ('HASH') { }
            default       { ... }
        }

        push @action,
          {
            controller => $self,
            name       => $name,
            pattern    => $pattern,
            code       => $code,
          };
    }
    $self->action(@action);

    return $self;
}

sub prefix {
    my $self   = shift;
    my $prefix = ref $self;
    return ( join q{/}, map { lc } split /::/, $prefix =~ s/\A\Q$self->{appname}\E//r ) . q{/};
}

1;
