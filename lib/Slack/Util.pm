package Slack::Util v0.2.5;
use v5.14.0;
use warnings;
use encoding::warnings;
use utf8;
use re 0.18 '/amsx';

BEGIN {
    # enable Smart::Comments for ownself
    if ( eval { require Smart::Comments; } ) {
        Smart::Comments->import(qw(-ENV));
    }
}

BEGIN {
    no warnings qw(redefine);    ## no critic qw(ProhibitNoWarnings)

    # Smart::Comments enhancer
    if ( not $INC{'Smart/Comments.pm'} ) {
        return;
    }

    require Data::Dumper;

    ## no critic qw(ProtectPrivateVars)

    # define human-readable dump
    my $dd_dump = \&Data::Dumper::_dump;
    my $hr_dump = sub {
        my @args = @_;

        # Time::Piece readable
        if ( eval { $args[1]->isa('Time::Piece') } ) {
            $args[1] = bless \( $args[1]->datetime ), ( ref $args[1] ) . '#stringify';
        }

        my $dumped = $dd_dump->(@args);

        # Regexp readable
        if ( $dumped =~ s{\A qr/ (.*) / \z}{$1} ) {
            $dumped =~ s{[\\](?=/)}{}g;
            $dumped =~ s{
                \A
                \Q(?^\E             # open parenthesis to clear modifiers
                (?<modifiers>.*?)
                :                   # delimiter
                (?<regexp>.*)
                \Q)\E               # close parenthesis
                \z
            }{qr{$+{regexp}}$+{modifiers}};
        }

        return $dumped;
    };

    my $hr_dumpperl = sub {
        my @args = @_;
        state $table = eval { require Text::Table::Tiny; \&Text::Table::Tiny::table };

        if (    $table
            and defined $args[1]->[0]->[0]
            and $args[1]->[0]->[0] eq 'rows'
            and ref $args[1]->[0]->[1] eq 'ARRAY'
            and ref $args[1]->[0]->[1]->[0] eq 'ARRAY' )
        {
            state $NAME  = 2;            # ClauseName
            state $VALUE = $NAME + 1;    # ClauseValue
            foreach my $row ( @{ $args[1]->[0]->[1] } ) {
                if ( ref $row->[$VALUE] ne 'Regexp' ) {
                    next;
                }

                # remove all the sequence Slack has added
                if ( $row->[$NAME] eq q{.} ) {
                    $row->[$VALUE] =~ s/ \Q(?^amsx:[.]\E (.*) \Q(?:[.]|\z))\E \z/$1/;
                }
                else {
                    $row->[$VALUE] =~ s/\A \Q(?^amsx:\A\E (.*) \Q\z)\E \z/$1/;
                    if ( $row->[$NAME] eq q{/} ) {
                        $row->[$VALUE] =~ s{\A/}{};
                    }
                }

                while (
                    $row->[$VALUE] =~ s{
                        (?<!\0)     # sentinel
                        [(]         # open parenthesis
                        (
                          (?:
                            [^()]*+ # non parenthesis
                            |       # or
                            (?R)    # recurse
                          )*
                        )
                        [)]         # close parenthesis
                    }{
                        my $inner = $1;

                        # remove modifiers
                        $inner =~ s/\A \Q?^\E? [adlupimsx]* (?:-[imsx]+)? (?|:(.+)|()) \z/$1/;

                        # remove named capture
                        $inner =~ s/\A [?]<.*?>//;

                        # remove embedded code
                        $inner =~ s/\A [?] [{] .* [}] \z//;

                        my $quantifiers = { map { $_ => 1 } qw(* + ?), "\x{7b}" };    # quantifiers
                        my $after = substr $row->[$VALUE], ( pos $row->[$VALUE] ) + ( length $inner ) + 2, 1;
                        if (
                            ( index $inner =~ s/[(][^()]*[)]//gr, q{|} ) != -1        # contains alternation
                            or $inner =~ /\A [?]{2} [{] .* [}] \z/                    # is interpolation code
                            or exists $quantifiers->{$after}                          # quantifier specified
                          )
                        {
                            $inner = "\0($inner)";
                        }
                        $inner;
                    }e
                  )
                {
                    # do nothing
                }
                $row->[$VALUE] =~ s/\0//g;    # remove sentinel

                $row->[$VALUE] =~ s/\A[(](.*)[)]\z/$1/g;    # remove outermost parenthesis

                # remove all the white spaces, comments and backslashes caused by qr//x
                $row->[$VALUE] =~ s/(?<![\\])[#][^]]*$//g;
                $row->[$VALUE] =~ s/(?<![\\])\s//g;
                $row->[$VALUE] =~ s{[\\](?=[- ./])}{}g;
            }

            # \e is hack for un-smart comments
            return "\n\e\n" . ( $table->( @{ $args[1]->[0] } ) =~ s/^/### /gr );
        }

        my $dumped = do {
            local *Data::Dumper::_dump = $hr_dump;
            Data::Dumper::Dumpperl(@args);
        };

        # decode Percent-Encoding
        $dumped =~ s/ [\\]x{ (\p{PosixXDigit}+) } /chr hex sprintf '%04s', $1/egi;

        # backslash readable
        $dumped =~ s/[\\](?=[\\])//g;

        return $dumped;
    };

    # Smart::Comments output encoding fix and readable
    my $sc_dump = \&Smart::Comments::_Dump;
    *Smart::Comments::_Dump = sub {
        binmode STDERR => ':encoding(UTF-8)';
        local *Data::Dumper::Dump = $hr_dumpperl;
        $sc_dump->( @_, nonl => 1 );
        binmode STDERR => ':pop';
    };
}

sub to_ref {
    my @arg = @_;
    if ( not @arg ) {
        return {};
    }

    state $single = { HASH => 1, ARRAY => 1 };
    if ( @arg == 1 and $single->{ ref $arg[0] } ) {
        return $arg[0];
    }

    # looks like not a hash
    if ( @arg % 2 == 1 ) {
        return \@arg;
    }

    # ditto
    for my $i ( 0 .. $#arg / 2 ) {
        if ( not defined $arg[ $i * 2 ] or ref $arg[ $i * 2 ] ) {
            return \@arg;
        }
    }

    # looks like a hash
    return {@arg};
}

sub import {
    my ( undef, @arg ) = @_;

    my $caller = caller;
    foreach my $method (@arg) {
        no strict qw(refs);    ## no critic qw(ProhibitNoStrict)
        *{ $caller . q{::} . $method } = *{ __PACKAGE__ . q{::} . $method }{CODE};
    }

    # enable Smart::Comments for caller
    if ( eval { require Smart::Comments; } ) {
        Smart::Comments->import(qw(-ENV));
    }

    return;
}

sub new {
    my ( $proto, @arg ) = @_;
    my $class = ref $proto || $proto;
    ### assert: $class ne __PACKAGE__
    return bless to_ref(@arg), $class;
}

1;
