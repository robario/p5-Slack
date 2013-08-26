package Slack::Controller v0.6.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use English qw(-no_match_vars);
use Filter::Simple;
use Slack::Action;
use Slack::Util;

FILTER_ONLY code => sub {
    no encoding::warnings;    # Do not decode the literals in the filter. If you use utf8, then please no utf8.

    state $keyword_pattern = join q{|}, qw(c req res);
    state $keyword_re      = qr/ \b (?<keyword>$keyword_pattern) \b /;
    state $asis_pattern    = join q{|}, (
        ## no critic qw(ValuesAndExpressions::RequireInterpolationOfMetachars)
        '\0\0',               # mark as literal by Filter::Simple
        q[{'],                # variable name or hash key
        '->',                 # method call
        quotemeta q{$#},      # last index op
        ( sprintf '.?[%s]', quotemeta '$@%*' ),    # symbol table lookup without `&`
        '(?!<&)&',                                 # symbol table lookup by `&` except `&&` op
    );
    state $asis_re = qr/\A (?:$asis_pattern) \z/;

    # mark as variable name or hash key
    s/ { \s* $keyword_re \s* } /{'$LAST_PAREN_MATCH{keyword}'}/g;

    # keyword expansion
    s{
      (?<before> \S{0,2} ) \s* \K    # keep because only for checking
      $keyword_re
      (?! \s* => )                   # avoid hash key
    }{
        my $keyword = $LAST_PAREN_MATCH{keyword};
        $LAST_PAREN_MATCH{before} =~ $asis_re ? $keyword : q{$} . '_[0]' . ( $keyword eq 'c' ? q{} : "->$keyword" );
    }eg;
};

sub import {
    ### assert: caller eq 'Slack'
    my $caller = caller 1;
    no strict qw(refs);    ## no critic qw(TestingAndDebugging::ProhibitNoStrict)
    *{ $caller . '::actions' } = [];
    foreach my $type (qw(prep action view)) {
        *{ $caller . q{::} . $type } = sub {
            if ( @_ == 2 ) {
                splice @_, 1, 0, $_[0];
            }
            ### assert: @_ == 3
            push @{ $caller . '::actions' }, [ $type, @_ ];
        };
    }
    return;
}

sub actions {
    my $class = shift;

    my $prefix = $class->prefix;
    ### assert: ref $prefix eq 'Regexp' or not ref $prefix and $prefix =~ qr{\A/} and $prefix =~ qr{/\z}
    ### assert: not ref $prefix or ref $prefix eq 'Regexp' and "$prefix" !~ qr/ [^\\] (?:[\\]{2})* [\\][Az] /
    my $actions = do {
        no strict qw(refs);    ## no critic qw(TestingAndDebugging::ProhibitNoStrict)
        *{ $class . '::actions' }{ARRAY};
    };
    foreach my $action ( @{$actions} ) {
        my ( $type, $name, $clause, $code ) = @{$action};

        if ( ref $clause ne 'HASH' ) {
            ### assert: not ref $clause or ref $clause eq 'Regexp' and "$clause" !~ qr/ [^\\] (?:[\\]{2})* [\\][Az] /
            $clause = { q{/} => $clause };
        }
        if ( not exists $clause->{PATH_INFO} ) {
            #### Generate PATH_INFO clause automatically...
            my $path = delete $clause->{q{/}};
            if ( defined $path ) {
                ### assert: not ref $path or ref $path eq 'Regexp'
                if ( not ref $path ) {
                    $path = quotemeta $path;
                }
            }
            else {
                $path = q{.*};
            }
            if ( exists $clause->{q{.}} ) {
                $path .= '[.]' . $clause->{q{.}};
            }
            $clause->{PATH_INFO} = qr{\A$prefix$path\z}p;
        }
        foreach my $key ( keys $clause ) {

            # $clause->{q{.}} will be removed by Slack::App
            if ( $key eq q{.} ) {
                next;
            }

            # fixed string should matches from \A to \z
            if ( not ref $clause->{$key} ) {
                $clause->{$key} = qr/\A$clause->{$key}\z/p;
            }
            ### assert: ref $clause->{$key} eq 'Regexp'
        }

        if ( ref $code eq 'CODE' ) {
            $code = { ( $type eq 'action' ? 'GET' : q{*} ) => $code };
        }
        if ( ref $code eq 'HASH' ) {
            ### assert: not exists $code->{HEAD}
            ### assert: $type ne 'action' or not exists $code->{q{*}}
        }
        else { ... }

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
