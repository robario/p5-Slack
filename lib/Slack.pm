package Slack v0.7.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use Module::Load qw(load);
use Slack::Util;

sub import {
    my ( undef, @args ) = @_;

    Slack::Util->import;    # for apply Smart::Comments to caller

    my $caller = caller;
    foreach my $component ( map { 'Slack::' . $_ } @args ) {
        load $component;
        $component->import;
        {
            no strict qw(refs);    ## no critic qw(TestingAndDebugging::ProhibitNoStrict)
            push @{ $caller . '::ISA' }, $component;
            if ( $component eq 'Slack::App' and not *{ $caller . '::import' }{CODE} ) {
                *{ $caller . '::import' } = sub {

                    # avoid calling Slack::Controller#import when $caller using multiple inheritance.
                    # This hack is no good idea.
                };
            }
        }
    }

    return;
}

1;

__END__

=head1 NAME

Slack - A slacked web application framework based on Plack

=head1 VERSION

This document describes Slack version v0.4.0

=head1 SYNOPSIS

  $ cat app.psgi
  use MyApp::Web;
  MyApp::Web->new;

  $ cat MyApp/Web.pm
  package MyApp::Web;
  use Slack qw(App);
  1;

  $ cat MyApp/Web/Hello.pm
  package MyApp::Web::Hello;
  use Slack qw(Controller);
  action world => sub {
      res->body('Hello, world!');
  };
  1;

  $ plackup
  HTTP::Server::PSGI: Accepting connections at http://0:5000/

  $ curl http://127.0.0.1:5000/hello/world
  Hello, world!

=head1 DESCRIPTION

=head1 SUBROUTINES/METHODS

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

Slack requires no configuration files or environment variables.

=head1 DEPENDENCIES

None.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests through the web interface at
L<https://github.com/robario/p5-Slack/issues>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 AUTHOR

robario <webmaster@robario.com>

=head1 LICENSE AND COPYRIGHT

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic|perlartistic>.

=cut
