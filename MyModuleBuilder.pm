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
    $self->delete_filetree('MANIFEST');
    $self->SUPER::ACTION_manifest(@_);
    return;
}

sub ACTION_manifest_skip {
    my $self = shift;
    $self->delete_filetree('MANIFEST.SKIP');
    $self->SUPER::ACTION_manifest_skip(@_);
    my $addition = sprintf <<'EOT', $self->dist_name;

# Avoid archives of this distribution (bugfix for Module::Build-0.4007)
\b%s-v?[\d\.\_]+

# Avoid local modules
^cpanfile.snapshot$
^local\b

# Avoid Test::Perl::Critic files.
^perltidy.LOG$
EOT
    open my $fh, '>>', 'MANIFEST.SKIP';
    $fh->print($addition);
    $fh->close;
    return;
}

sub ACTION_realclean {
    my $self = shift;
    $self->add_to_cleanup(
        qw(
          cpanfile.snapshot
          perltidy.LOG
          MANIFEST.bak
          MANIFEST.SKIP.bak
          ),
        $self->dist_dir . '.tar.gz',
    );
    $self->SUPER::ACTION_realclean(@_);
    return;
}

1;
