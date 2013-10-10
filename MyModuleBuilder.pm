package MyModuleBuilder v0.0.0;
use v5.14.0;
use warnings;
use encoding::warnings;

use autodie qw(open);
use parent qw(Module::Build);

## no critic qw(Capitalization)

sub ACTION_manifest {
    my $self = shift;
    $self->depends_on('manifest_skip');
    unlink 'MANIFEST';
    $self->SUPER::ACTION_manifest;
    return;
}

sub ACTION_manifest_skip {
    my $self = shift;
    unlink 'MANIFEST.SKIP';
    $self->SUPER::ACTION_manifest_skip(@_);
    open my $fh, '>>', 'MANIFEST.SKIP';
    $fh->print(<<'EOT');

# Avoid archives of this distribution
\bSlack-v[\d\.\_]+  # bugfix Module::Build-0.4007

# Avoid local modules
^local/
EOT
    $fh->close;
    return;
}

sub ACTION_realclean {
    my $self = shift;
    $self->add_to_cleanup(
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
    );
    $self->SUPER::ACTION_realclean(@_);
    return;
}

1;
