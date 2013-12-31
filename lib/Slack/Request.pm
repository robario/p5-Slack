package Slack::Request v0.3.3;
use v5.14.0;
use warnings;
use encoding::warnings;

use parent qw(Plack::Request);
use Encode qw(find_encoding);
use Plack::Util::Accessor qw(args argv);
use Slack::Util;

sub new {
    my ( undef, $env ) = @_;
    my $encoder = find_encoding('UTF-8');    # FIXME: guess encoding
    $env->{PATH_INFO} = $encoder->decode( $env->{PATH_INFO} );
    goto \&Plack::Request::new;
}

sub parameters {
    my ($self) = @_;
    state $param_for = {
        ( map { $_ => \&Plack::Request::query_parameters } qw(HEAD GET) ),
        ( map { $_ => \&Plack::Request::body_parameters } qw(POST PUT DELETE) ),
    };

    goto $param_for->{ $self->method };
}

1;
