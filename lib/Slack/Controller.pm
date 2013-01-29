package Slack::Controller v0.2.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Filter::Simple;
use Plack::Component;
use Plack::Util::Accessor qw(config action);

FILTER_ONLY code => sub {
    s/\bcontext\b(?!\s*=)/\$_[0]/g;
    s/\breq\b(?!\s*=)/\$_[1]/g;
    s/\bres\b(?!\s*=)/\$_[2]/g;
};

my @action;

sub import {
    ### assert: caller eq 'Slack'
    my $package = caller 1;
    no strict qw(refs);    ## no critic (TestingAndDebugging::ProhibitNoStrict)
    *{ $package . '::action' } = sub {
        ### assert: @_ == 2 or @_ == 3
        push @action, \@_;
        return;
    };
    return;
}

sub new {
    my ( $class, %option ) = @_;
    ### assert: $class ne __PACKAGE__
    {
        # restore action accessor
        no strict qw(refs);    ## no critic (TestingAndDebugging::ProhibitNoStrict)
        undef *{ $class . '::action' };
    }
    $option{action} = [];
    my $self = Plack::Component::new( $class, %option );

    my $prefix = $self->prefix;
    ### assert: $prefix =~ qr{\A/}
    while ( my $action = shift @action ) {
        my $name    = $action->[0];
        my $pattern = @{$action} == 2 ? $name : $action->[1];
        my $code    = @{$action} == 2 ? $action->[1] : $action->[2];

        given ( ref $pattern ) {
            when (q{}) {
                $pattern = quotemeta $pattern;
                $pattern = qr/$pattern\z/;
            }
            when ('Regexp') { }
            default         { ... }
        }
        $pattern = qr{\A$prefix$pattern};

        given ( ref $code ) {
            when ('CODE') { $code = { GET => $code }; }
            when ('HASH') { }
            default       { ... }
        }

        push $self->action, { name => $name, pattern => $pattern, code => $code };
    }

    return $self;
}

sub prefix {
    my $self    = shift;
    my $prefix  = ref $self;
    my $appname = quotemeta $self->{_appname};
    return ( join q{/}, map { lc } split /::/, $prefix =~ s/\A$appname//r ) . q{/};
}

1;
