#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.2;
use v5.14.0;
use warnings;
use encoding::warnings;

use re qw(/amsx);
use B::Deparse;
use Test::More;

# FIXME: B::Deparse ignores all comments, so could not test for Smart::Comments
sub deparse {
    my $coderef = shift;

    my $text = B::Deparse->new->coderef2text($coderef);

    # remove indent
    $text =~ s/^[ ]*//g;

    # cutoff
    $text =~ s{
        \A .*?\R \N{RIGHT CURLY BRACKET}\R     # header
        (.*)
        return;\R \N{RIGHT CURLY BRACKET} \z   # footer
    }{$1};

    return split /\R/, $text;
}

## no critic qw(ValuesAndExpressions::RequireInterpolationOfMetachars)
is_deeply(
    [ deparse( \&MyApp::method ) ],
    [
        # various pattern
        '$_[0];',
        '$_[0]->req;',
        '$_[0]->res;',
        '$_[0]->req;',
        q{+{'c', $_[0]};},
        q{$$foo{'c'};},
        ( '{', '$_[0]->req, $_[0];', '}' ),
        '$foo = $_[0];',
        q{'???';},
        q{'???';},
        q{'???';},

        # variable names should not be replaced
        ( qw($c; @c; %c; &c; *c;), '$#c;' ),
        ( qw($c; @c; %c; &c; *c;), '$#c;' ),

        # strange spaces
        qw($c; @c; %c; &c; *c;),
        ( qw($c; @c; %c; &c; *c;), '$#c;' ),
        '$foo->c;',
        '$_[0]->req;',
        ( '{', '$_[0]->req, $_[0];', '}' ),
        '$_[0];',
        '$_[0];',
        '-$_[0];',
        '$_[0];',
        '1 - $_[0];',
        '1 - $_[0];',
        '1 | $_[0];',
        '1 | $_[0];',
        '$_[0];',
        '$_[0];',
    ],
    'keyword replace'
);

TODO: {
    local $TODO = 'hard syntax';
    my @expected = (
        '1 & $_[0];'      => 'misunderstood subroutine',
        '1 & $_[0];'      => 'misunderstood subroutine',
        '1 % $_[0];'      => 'misunderstood hash variable',
        '1 % $_[0];'      => 'misunderstood hash variable',
        '1 * $_[0];'      => 'misunderstood glob',
        '1 * $_[0];'      => 'misunderstood glob',
        'undef // $_[0];' => 'bug of Filter::Simple',
        'undef // $_[0];' => 'bug of Filter::Simple',
    );
    my @got = deparse( \&MyApp::todo );
    foreach my $i ( 0 .. $#got ) {
        is( $got[$i], $expected[ 2 * $i ], $expected[ 2 * $i + 1 ] );
    }
}

done_testing;

package MyApp;    ## no critic qw(Modules::ProhibitMultiplePackages)
no strict         ## no critic qw(TestingAndDebugging::ProhibitNoStrict TestingAndDebugging::ProhibitProlongedStrictureOverride)
  qw(
  subs
  vars
);
no warnings qw(ambiguous reserved void);    ## no critic qw(TestingAndDebugging::ProhibitNoWarnings)
use Slack qw(Controller);

## no critic qw(References::ProhibitDoubleSigils Subroutines::ProhibitAmpersandSigils)
sub method {

    # various pattern
    c;
    req;
    res;
    c->req;                                 # lhs is replaced but rhs is a method call is as it is
    { c => c };                             # hash key is as it is
    $foo->{c};                              # hash key is as it is
    { c->req => c };                        # lhs is not a bareword, so treat with expression
    $foo = c;                               # assignment
    ac;
    cz;
    acz;

    # variable names should not be replaced
    $c;
    @c;
    %c;
    &c;
    *c;
    $#c;
    ${c};
    @{c};
    %{c};
    &{c};
    *{c};
    $#{c};

    # strange spaces
    #<<<
    $ c ;
    @ c ;
    % c ;
    & c ;
    * c ;
    # $# c;    # syntax error
    ${ c } ;
    @{ c } ;
    %{ c } ;
    &{ c } ;
    *{ c } ;
    $#{ c } ;
    $foo -> c;
    c -> req;
    {c->req=>c};
    1 && c;
    1&&c;
    -c;
    +c;
    1 -c;
    1 - c;
    1 | c;
    1|c;
    0 || c;
    0||c;
    #>>>

    return;
}

sub todo {

    # strange spaces
    #<<<
    1 & c;
    1&c;
    1 % c;
    1%c;
    1 * c;
    1*c;
    undef//c;
    undef // c;
    #>>>

    return;
}
