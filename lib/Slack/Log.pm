package Slack::Log v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Encode qw(encode_utf8);
use Text::Balanced qw(extract_quotelike);

sub import {
    eval { require Smart::Comments; };
    if ($@) {
        return;
    }

    no warnings qw(redefine);

    my $Dumper = Smart::Comments->can('Dumper');
    *Smart::Comments::Dumper = sub {
        my $dumped = $Dumper->(@_);
        $dumped =~ s/\\x{([0-9A-Fa-f]+)}/chr hex sprintf '%04s', $1/eg;
        $dumped =~ s/\\\\/\\/g;
        $dumped =~ s{\b(qr/.*)}{
                my $x = $1;
                my ($extracted, $remainder) = extract_quotelike($x);
                $extracted =~ s{\\/}{/}g;
                $extracted =~ s{\Aqr/\Q(?^\E([^:]+):(.+)[)]/\z}{qr{$2}$1};
                $extracted =~ s{\Aqr/(.+)/\z}{$1};
                $extracted . $remainder;
            }eg;
        return encode_utf8($dumped);
    };

    my $import = warnings->can('import');
    *warnings::import = sub {
        my $package = caller;
        eval qq{
            package $package;
            Smart::Comments->import(qw(-ENV));
        };
        goto &{$import};
    };
    warnings->import;
}

1;
