package Slack::Log v0.1.1;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

BEGIN {
    eval { require Smart::Comments; } or return;

    no warnings qw(redefine);    ## no critic (TestingAndDebugging::ProhibitNoWarnings)

    my $dumper = \&Smart::Comments::Dumper;
    *Smart::Comments::Dumper = sub {
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
        require Encode;
        return Encode::encode_utf8($dumped);
    };

    # Even if warnings is loaded instead of Slack::Log, enable Smart::Comments.
    my $import = \&warnings::import;
    *warnings::import = sub {
        Smart::Comments->import(qw(-ENV));
        goto &{$import};
    };
}

sub import {
    warnings->import;
    return;
}

1;
