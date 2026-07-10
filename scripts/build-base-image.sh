#!/usr/bin/env bash
# Build the tailwind-builder base (toolchain) image locally.
#
# The default `docker buildx` docker-container driver boots a buildkit container
# that fails to mount nested overlayfs on many hosts ("failed to mount ...
# overlay ... invalid argument"). Two working paths, same as CI:
#
#   1. REMOTE buildkitd (preferred, what .woodpecker/docker-image.yml uses):
#      set BUILDKIT_HOST_AMD64 / BUILDKIT_HOST_ARM64 to a buildkitd endpoint
#      (e.g. tcp://127.0.0.1:1234 after `kubectl -n defdo-ci port-forward
#      svc/buildkit-amd64 1234:1234`). The remote daemon does the build + push.
#
#   2. Local docker-container driver with the `native` snapshotter (fallback),
#      which copies instead of mounting overlay, avoiding the nested-overlay bug.
#
# Usage:
#   scripts/build-base-image.sh <tag> [amd64|arm64]
#   BUILDKIT_HOST_AMD64=tcp://127.0.0.1:1234 scripts/build-base-image.sh 0.2.6 amd64
set -euo pipefail

TAG="${1:?usage: build-base-image.sh <tag> [amd64|arm64]}"
ARCH="${2:-amd64}"
REPO="${REPO:-hub.defdo.ninja/defdo/tailwind-builder}"
DOCKERFILE="docker/tailwind-builder-v4/Dockerfile"
PLATFORM="linux/${ARCH}"
IMAGE="${REPO}:${TAG}-${ARCH}"
BUILDER="tailwind-builder-${ARCH}"

# Pick the remote endpoint for the requested arch.
case "$ARCH" in
  amd64) ENDPOINT="${BUILDKIT_HOST_AMD64:-}";;
  arm64) ENDPOINT="${BUILDKIT_HOST_ARM64:-}";;
  *) echo "unknown arch: $ARCH" >&2; exit 2;;
esac

docker buildx rm "$BUILDER" >/dev/null 2>&1 || true

if [ -n "$ENDPOINT" ]; then
  echo ">> remote buildkitd driver: $ENDPOINT"
  docker buildx create --name "$BUILDER" --driver remote "$ENDPOINT" --use
else
  echo ">> no BUILDKIT_HOST_${ARCH^^} set — local docker-container driver (native snapshotter)"
  docker buildx create --name "$BUILDER" --driver docker-container \
    --driver-opt env.BUILDKITD_FLAGS="--oci-worker-snapshotter=native" --use
fi

docker buildx build --rm=true -f "$DOCKERFILE" . \
  --pull=true \
  --platform "$PLATFORM" \
  --output "type=image,push=true,rewrite-timestamp=true" \
  -t "$IMAGE" \
  --label "org.opencontainers.image.version=${TAG}" \
  --label "org.opencontainers.image.revision=$(git rev-parse HEAD)"

echo ">> pushed ${IMAGE}"
echo ">> compose multi-arch after building both arches:"
echo "   docker buildx imagetools create -t ${REPO}:${TAG} ${REPO}:${TAG}-amd64 ${REPO}:${TAG}-arm64"
