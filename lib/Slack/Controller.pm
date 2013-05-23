package Slack::Controller v0.3.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Filter::Simple;
use Plack::Component;
use Slack::Util;

FILTER_ONLY code => sub {
    state $replacement = {
        ## no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)
        req => '$_[3]',
        res => '$_[4]',
    };
    while ( my ( $keyword, $expression ) = each $replacement ) {
        s/(?<![\$@%&*])(?<!->)$keyword\b(?!\s*=>)/$expression/g;
    }
};

sub import {
    my $class = shift;
    ### assert: caller eq 'Slack'
    my $caller = caller 1;
    foreach my $type (qw(view action)) {
        no strict qw(refs);    ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{ $caller . q{::} . $type } = $class->_create_stacker();
    }
    return;
}

sub _create_stacker {
    my @source;
    return sub {
        my ($self) = @_;

        if ( not $self->isa(__PACKAGE__) ) {
            ### assert: @_ == 2 or @_ == 3
            push @source, \@_;
            return;
        }

        # reconstruct matchers
        my $prefix = $self->prefix;
        ### assert: $prefix =~ qr{\A/} and $prefix =~ qr{/\z}
        my @matcher;
        foreach my $source (@source) {
            my $name    = shift $source;
            my $pattern = @{$source} == 1 ? $name : shift $source;
            my $code    = shift $source;
            my $extension;

            if ( ref $pattern eq q{} ) {
                $pattern = qr{\A$prefix\Q$pattern\E\z}p;
            }
            elsif ( ref $pattern eq 'HASH' ) {    # XXX: view only
                ### assert: length $pattern->{extension}
                ### assert: q{.} ne substr $pattern->{extension}, 0, 1
                $extension = $pattern->{extension};
                $pattern   = qr{\A$prefix.*[.]$extension\z}p;
            }
            elsif ( ref $pattern eq 'Regexp' ) {
                $pattern = qr{\A$prefix$pattern}p;
            }
            else { ... }

            if ( ref $code eq 'CODE' ) {
                $code = { GET => $code };
            }
            elsif ( ref $code eq 'HASH' ) {
                ### assert: scalar keys $code == scalar grep { $_ =~ qr/\A(?:HEAD|GET|POST|PUT|DELETE)\z/ } keys $code;
            }
            else { ... }

            push @matcher,
              {
                controller => $self,
                name       => $name,
                pattern    => $pattern,
                extension  => $extension,
                code       => $code,
              };
        }
        return @matcher;
    };
}

sub new {
    my ( $class, @args ) = @_;
    ### assert: $class ne __PACKAGE__
    goto \&Plack::Component::new;
}

sub prefix {
    my $self = shift;
    return $self->{prefix};
}

1;
