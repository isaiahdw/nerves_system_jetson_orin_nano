#!/bin/sh

set -e

FWUP_CONFIG=$NERVES_DEFCONFIG_DIR/fwup.conf

# Run the common post-image processing for nerves
$BR2_EXTERNAL_NERVES_PATH/board/nerves-common/post-createfs.sh $TARGET_DIR $FWUP_CONFIG

# Drop the previous build's portable artifact before this one's is written.
#
# The container build volume is buildroot's output directory, and every build
# adds a portable tarball to it while removing none of the earlier ones. The
# artifact firmware builds actually consume is copied out to
# ~/.nerves/artifacts on the host, so the copies in here are duplicates from
# the moment they are made. See nerves_system_sige5's post-createfs.sh for
# the full history; the volume's virtio-blk device has no discard support,
# so space already lost needs the volume deleted
# (tools/prune-build-volume.sh).
BUILD_ROOT=${BASE_DIR:-${BINARIES_DIR:+$BINARIES_DIR/..}}
if [ -n "$BUILD_ROOT" ] && [ -d "$BUILD_ROOT" ]; then
    stale=$(find "$BUILD_ROOT" -maxdepth 1 -name 'nerves_system_*-portable-*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')
    find "$BUILD_ROOT" -maxdepth 1 -name 'nerves_system_*-portable-*.tar.gz' -delete 2>/dev/null || true
    echo "post-createfs: removed $stale stale portable artifact(s) from $BUILD_ROOT"
else
    echo "post-createfs: no BASE_DIR/BINARIES_DIR, skipping artifact prune" >&2
fi
