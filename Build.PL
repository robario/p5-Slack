#! /usr/bin/perl
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;

package main v0.1.4;
use v5.14.0;
use warnings;
use encoding::warnings;

use Module::Build;
use Module::CPANfile;

sub specs2mb {
    my $specs = shift;
    return (
        configure_requires => $specs->{configure}->{requires} // {},
        build_requires     => $specs->{build}->{requires}     // {},
        requires           => $specs->{runtime}->{requires}   // {},
        test_requires      => $specs->{test}->{requires}      // {},
        recommends => { map { %{ @{ $specs->{$_} }{qw(recommends suggests)} // {} } } keys $specs },
        conflicts => { map { %{ $specs->{$_}->{conflicts} // {} } } keys $specs },
    );
}

my $cpanfile = Module::CPANfile->load;

Module::Build->subclass(
    code => <<'CODE',
sub ACTION_manifest_skip {
    my $self = shift;
    $self->SUPER::ACTION_manifest_skip(@_);
    use autodie;
    open my $fh, '>>', 'MANIFEST.SKIP';
    $fh->print(<<'EOT');

# Addition
\.ERR$
\.LOG$
\.tdy$
^Slack\.ppd
EOT
    $fh->close;
    return;
}
CODE
  )->new(
    module_name => 'Slack',
    specs2mb( $cpanfile->prereq_specs ),
    auto_features  => { map { $_->identifier => { specs2mb( $_->prereqs->as_string_hash ) } } $cpanfile->features },
    add_to_cleanup => [
        qw(
          *.ERR
          *.LOG
          *.bak
          *.tdy
          *.tmp
          MANIFEST
          MANIFEST.SKIP
          META.json
          META.yml
          Slack-*.tar.gz
          )
    ],
  )->create_build_script;
