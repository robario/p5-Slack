package Slack::Controller v0.8.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use re qw(/amsx);
use Slack::Action;
use Slack::Util;

sub import {
    ### assert: caller eq 'Slack'
    my $caller = caller 1;
    no strict qw(refs);    ## no critic qw(ProhibitNoStrict ProhibitProlongedStrictureOverride)
    *{ $caller . '::actions' } = [];
    foreach my $type (qw(prep action view)) {
        *{ $caller . q{::} . $type } = sub {
            if ( @_ == 2 ) {
                splice @_, 1, 0, $type eq 'action' ? { q{/} => $_[0] } : {};
            }
            ### assert: @_ == 3
            push @{ $caller . '::actions' }, [ $type, @_ ];
        };
    }

    foreach my $keyword (qw(c req res)) {
        *{ $caller . q{::} . $keyword } = sub {
            { package DB; () = caller 1; }    ## no critic qw(ProhibitMultiplePackages)
            return $DB::args[0]->$keyword;    ## no critic qw(ProhibitPackageVars)
        };
    }

    return;
}

sub actions {
    my $class = shift;

    my $prefix = $class->prefix;
    ### assert: defined $prefix
    ### assert: ref $prefix eq 'Regexp' or not ref $prefix and $prefix =~ m{\A / (?:.+/)? \z}
    ### assert: not ref $prefix or ref $prefix eq 'Regexp' and "$prefix" !~ / [^\\] (?:[\\]{2})* [\\][Az] /
    my $actions = do {
        no strict qw(refs);    ## no critic qw(ProhibitNoStrict)
        *{ $class . '::actions' }{ARRAY};
    };
    foreach my $action ( @{$actions} ) {
        my ( $type, $name, $clause, $code ) = @{$action};

        # ensure clause is a hash
        if ( ref $clause ne 'HASH' ) {
            $clause = { q{/} => $clause };
        }

        # to add a prefix even if unconditional
        if ( not defined $clause->{PATH_INFO} and not defined $clause->{q{/}} ) {
            if ( $prefix ne q{/} ) {    # because meaningless
                $clause->{q{/}} = qr/.*/;
            }
        }

        # fixup / clause
        if ( defined $clause->{q{/}} ) {
            ### assert: not ref $clause->{q{/}} or ref $clause->{q{/}} eq 'Regexp' and "$clause->{q{/}}" !~ / [^\\] (?:[\\]{2})* [\\][Az] /
            if ( not ref $clause->{q{/}} ) {
                $clause->{q{/}} = quotemeta $clause->{q{/}};
            }
            $clause->{q{/}} = qr{\A$prefix$clause->{q{/}}\z};
        }

        # fixup . clause
        if ( defined $clause->{q{.}} ) {
            ### assert: not ref $clause->{q{.}} or ref $clause->{q{.}} eq 'Regexp' and "$clause->{q{.}}" !~ / [^\\] (?:[\\]{2})* [\\][Az] /
            if ( not ref $clause->{q{.}} ) {
                $clause->{q{.}} = quotemeta $clause->{q{.}};
            }
            $clause->{q{.}} = qr/[.]$clause->{q{.}}(?:[.]|\z)/;
        }

        # ensure regexp values of all of the clause
        foreach my $key ( keys $clause ) {
            if ( not defined $clause->{$key} ) {
                delete $clause->{$key};
                next;
            }

            # fixed string should be quotemeta and matched to \A and \z
            if ( not ref $clause->{$key} ) {
                $clause->{$key} = qr/\A\Q$clause->{$key}\E\z/;
            }
            ### assert: ref $clause->{$key} eq 'Regexp'
        }

        # fixup code
        if ( ref $code eq 'CODE' ) {
            $code = { ( $type eq 'action' ? 'GET' : q{*} ) => $code };
        }
        ### assert: ref $code eq 'HASH'
        ### assert: not exists $code->{HEAD}
        ### assert: $type ne 'action' or not exists $code->{q{*}}
        if ( not defined $clause->{REQUEST_METHOD} and not exists $code->{q{*}} ) {
            $clause->{REQUEST_METHOD} = join q{|}, keys $code;
            if ( exists $code->{GET} ) {
                $clause->{REQUEST_METHOD} .= '|HEAD';
            }
            $clause->{REQUEST_METHOD} = qr/\A(?:$clause->{REQUEST_METHOD})\z/;
        }

        $action = Slack::Action->new(
            clause     => $clause,
            code       => $code,
            controller => $class,
            name       => $name,
            type       => $type,
        );
    }
    return @{$actions};
}

1;
