package Slack::Util v0.0.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Encode qw(decode_utf8);
use Time::Piece;

BEGIN {    ## no critic (Subroutines::RequireArgUnpacking)
    ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    ## no critic (Variables::ProtectPrivateVars)
    no warnings qw(redefine);
    my $_strftime = \&Time::Piece::_strftime;
    *Time::Piece::_strftime = sub ($$$$$$$;$$$) {
        return decode_utf8( $_strftime->(@_) );
    };

    # Smart::Comments debug enhancer
    eval { require Smart::Comments; } or return;

    my $_dump = \&Data::Dumper::_dump;

    sub _dump {
        my @args = @_;

        # make Time::Piece object readable
        if ( ref $args[1] eq 'Time::Piece' ) {
            $args[1] = bless \( $args[1]->datetime ), ( ref $args[1] ) . '#stringify';
        }
        return $_dump->(@args);
    }
    my $dumper = \&Smart::Comments::Dumper;
    *Smart::Comments::Dumper = sub {
        local $Data::Dumper::Useperl = 1;
        local *Data::Dumper::_dump   = \&_dump;
        my $dumped = $dumper->(@_);

        # make unicode characters visible
        $dumped =~ s/\\x{([\dA-F]+)}/chr hex sprintf '%04s', $1/egi;

        # make backslash readable
        $dumped =~ s/\\\\/\\/g;

        # make regular expression readable (qr/\// => qr{/})
        $dumped =~ s{\b(qr/.*)}{
                my $x = $1;
                require Text::Balanced;
                my ($extracted, $remainder) = Text::Balanced::extract_quotelike($x);
                $extracted =~ s{\\/}{/}g;
                $extracted =~ s{\Aqr/\Q(?^\E([^:]+):(.+)[)]/\z}{qr{$2}$1};
                $extracted =~ s{\Aqr/(.+)/\z}{$1};
                $extracted . $remainder;
            }eg;
        return Encode::encode_utf8($dumped);
    };

    # Even if warnings is loaded instead of Slack::Util, enable Smart::Comments.
    my $import = \&warnings::import;
    *warnings::import = sub {
        Smart::Comments->import(qw(-ENV));
        goto &{$import};
    };
    ## use critic
}

sub import {
    warnings->import;
    return;
}

1;
