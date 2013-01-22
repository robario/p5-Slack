package Slack::Controller v0.1.0;
use v5.12.0;
use warnings;
use encoding::warnings;
use re qw(/msx);

use Slack ();    # avoid import
use Filter::Simple;
use Plack::Component;
use Plack::Util::Accessor qw(config);

FILTER_ONLY code => sub {
    s/\bcontext\b(?!\s*=)/\$_[0]/g;
    s/\breq\b(?!\s*=)/\$_[1]/g;
    s/\bres\b(?!\s*=)/\$_[2]/g;
};

*new = \&Plack::Component::new;

1;
