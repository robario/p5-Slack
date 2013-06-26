package Slack::Controller v0.4.0;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Encode qw(find_encoding);
use English qw(-no_match_vars);
use Filter::Simple;
use Slack::Matcher;
use Slack::Util qw(new);

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
    foreach my $type (qw(view action)) {
        no strict qw(refs);    ## no critic qw(TestingAndDebugging::ProhibitNoStrict)
        *{ $caller . q{::} . $type } = __PACKAGE__->_create_stacker();
    }
    return;
}

sub _create_stacker {
    my @source;
    return sub {
        my ($self) = @_;

        if ( not $self->isa(__PACKAGE__) ) {
            if ( @_ == 2 ) {
                splice @_, 1, 0, $_[0];
            }
            ### assert: @_ == 3
            push @source, \@_;
            return;
        }

        # reconstruct matchers
        my $prefix = $self->prefix;
        ### assert: ref $prefix eq 'Regexp' or not ref $prefix and $prefix =~ qr{\A/} and $prefix =~ qr{/\z}
        ### assert: not ref $prefix or ref $prefix eq 'Regexp' and "$prefix" !~ qr/ [^\\] (?:[\\]{2})* [\\][Az] /
        my @matcher;
        foreach my $source (@source) {
            my ( $name, $pattern, $code ) = @{$source};
            my $extension;

            ### assert: "$pattern" !~ qr/ [^\\] (?:[\\]{2})* [\\][Az] /
            if ( not ref $pattern ) {
                $pattern = qr{\A$prefix\Q$pattern\E\z}p;
            }
            elsif ( ref $pattern eq 'HASH' ) {    # XXX: view only
                ### assert: length $pattern->{extension}
                ### assert: q{.} ne substr $pattern->{extension}, 0, 1
                $extension = $pattern->{extension};
                $pattern   = qr{\A$prefix.*[.]$extension\z}p;
            }
            elsif ( ref $pattern eq 'Regexp' ) {
                $pattern = qr{\A$prefix$pattern\z}p;
            }
            else { ... }

            if ( ref $code eq 'CODE' ) {
                $code = { GET => $code };
            }
            elsif ( ref $code eq 'HASH' ) {
                ### assert: not exists $code->{HEAD}
            }
            else { ... }

            push @matcher,
              Slack::Matcher->new(
                code       => $code,
                controller => $self,
                extension  => $extension,
                name       => $name,
                pattern    => $pattern,
              );
        }
        return @matcher;
    };
}

1;
