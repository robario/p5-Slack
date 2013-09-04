package Slack::Util v0.2.2;
use v5.14.0;
use warnings;
use encoding::warnings;
use re qw(/msx);
use version;

use Carp qw(carp);
use Data::Dumper;
use Encode qw(find_encoding);

BEGIN {
    # enable Smart::Comments for ownself
    if ( eval { require Smart::Comments; } ) {
        Smart::Comments->import(qw(-ENV));
    }
}

BEGIN {
    no warnings qw(redefine);    ## no critic qw(TestingAndDebugging::ProhibitNoWarnings)

    my $patch_for = sub {
        my ( $class, $version ) = @_;
        if ( version->parse($version) < version->parse( $class->VERSION ) ) {
            carp( sprintf 'Please check the patch for %s-%s, installed version %s is higher', $class, $version, $class->VERSION );
        }
    };

    # Smart::Comments enhancer
    if ( not $INC{'Smart/Comments.pm'} ) {
        return;
    }
    $patch_for->( 'Data::Dumper'    => '2.145' );
    $patch_for->( 'Smart::Comments' => '1.000005' );

    # define human-readable dump
    ## no critic qw(Variables::ProtectPrivateVars)
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
                [(]\Q?^\E       # open paren to clear flags
                (?<flags>.*?)
                :               # delimiter
                (?<regexp>.*)
                [)]             # close paren
                \z
            }{qr{$+{regexp}}$+{flags}};
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

                # remove all the flags
                while (
                    $row->[$VALUE] =~ s{
                        (?<!\0)     # sentinel
                        [(]         # open paren
                        (
                          (?:
                            [^()]*+ # non paren
                            |       # or
                            (?R)    # recurse
                          )*
                        )
                        [)]         # close paren
                    }{
                        my $inner = $1;
                        if ( $inner =~ s/\A[?][^:]+(?::|\z)// ) {
                            $inner;
                        }
                        else {
                            $inner =~ s/\A[?]://;
                            "\0($inner)";
                        }
                    }e
                  )
                {
                }
                $row->[$VALUE] =~ s/\0//g;    # remove sentinel

                # remove all the sequence Slack has added
                $row->[$VALUE] =~ s/\A (?:[\\]A)? (.*?) (?:[\\]z)? \z/$1/;
                if ( $row->[$NAME] eq q{.} ) {
                    $row->[$VALUE] =~ s/\A \Q[.]\E (.*) \Q([.]|\z)\E \z/$1/;
                }
                elsif ( $row->[$NAME] eq q{/} ) {
                    $row->[$VALUE] =~ s{\A/}{};
                }

                # remove all the white spaces and backslashes caused by qr//x
                $row->[$VALUE] =~ s/(?<![\\])\s//g;
                $row->[$VALUE] =~ s{[\\](?=[- /])}{}g;
            }

            # \e is hack for un-smart comments
            return "\n\e\n" . ( $table->( @{ $args[1]->[0] } ) =~ s/^/### /gr );
        }

        my $dumped = do {
            local *Data::Dumper::_dump = $hr_dump;
            Data::Dumper::Dumpperl(@args);
        };

        # decode Percent-Encoding
        $dumped =~ s/ [\\]x{ ([\dA-F]+) } /chr hex sprintf '%04s', $1/egi;

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
        no strict qw(refs);    ## no critic qw(TestingAndDebugging::ProhibitNoStrict)
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
