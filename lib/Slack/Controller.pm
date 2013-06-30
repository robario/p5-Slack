package Slack::Controller v0.4.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Encode qw(find_encoding);
use English qw(-no_match_vars);
use Filter::Simple;
use Slack::Action;
use Slack::Util;

FILTER_ONLY code => sub {
    state $keyword_pattern = join q{|}, qw(c req res);
    state $keyword_re      = qr/ \b (?<keyword>$keyword_pattern) \b /;
    state $asis_pattern    = join q{|}, (
        ## no critic qw(ValuesAndExpressions::RequireInterpolationOfMetachars)
        q[{'],              # variable name or hash key
        '->',               # method call
        quotemeta q{$#},    # last index op
        ( sprintf '.?[%s]', quotemeta '$@%*' ),    # symbol table lookup without `&`
        '(?!<&)&',                                 # symbol table lookup by `&` except `&&` op
    );
    state $asis_re = qr/\A (?:$asis_pattern) \z/;

    my $encoder = find_encoding('UTF-8');          # FIXME: guess encoding
    $_ = $encoder->decode($_);

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

    $_ = $encoder->encode($_);
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

        if ( exists $clause->{q{extension}} ) {
            warnings::warnif( deprecated => 'clause parameter "extension" is deprecated; use "." instead' );
            $clause->{q{.}} = delete $clause->{q{extension}};
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
            $code = { GET => $code };
        }
        elsif ( ref $code eq 'HASH' ) {
            ### assert: not exists $code->{HEAD}
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
