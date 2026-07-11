#!/usr/bin/env bash
# Build the tailwind-builder base (toolchain) image locally.
#
# TWO problems bite a local base-image build; both are solved here:
#
#   A. The default docker-container buildx driver boots a buildkit container that
#      fails to mount nested overlayfs ("overlay ... invalid argument"). Fix: the
#      `native` snapshotter (copy, no overlay) — used automatically below.
#
#   B. The base has a large NEW layer (rust ~614MB). Pushing to hub.defdo.ninja
#      goes through Cloudflare, which rejects bodies >~100MB with "413 Payload
#      Too Large" (the remote in-cluster buildkitd ALSO resolves hub.defdo.ninja
#      to Cloudflare, so it 413s too — the CI only escapes this for the *worker*
#      image because same-repo base layers are skipped and only ~9MB is pushed).
#      Fix: push straight to the INTERNAL Harbor IP (same registry, LAN, no CF):
#
#        REPO=192.168.13.209/defdo/tailwind-builder \
#          scripts/build-base-image.sh 0.2.6 amd64
#
#      Requirements for the internal push (Harbor's cert CN is hub.defdo.ninja,
#      not the IP, so TLS to the IP needs insecure-registries):
#        - dockerd daemon.json: {"insecure-registries": ["192.168.13.209"]}  (restart docker)
#        - docker login 192.168.13.209   (same Harbor creds)
#      The image lands in the same Harbor repo, pullable in-cluster as
#      hub.defdo.ninja/defdo/tailwind-builder:<tag>.
#
# Usage:
#   REPO=192.168.13.209/defdo/tailwind-builder scripts/build-base-image.sh <tag> [amd64|arm64]
set -euo pipefail

TAG="${1:?usage: build-base-image.sh <tag> [amd64|arm64]}"
ARCH="${2:-amd64}"
# Default to the INTERNAL Harbor IP to dodge Cloudflare's 413 on large layers.
REPO="${REPO:-192.168.13.209/defdo/tailwind-builder}"
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
  echo ">> local docker-container driver (native snapshotter, no nested overlay)"
  case "$REPO" in
    hub.defdo.ninja/*)
      echo "!! WARNING: REPO targets hub.defdo.ninja (Cloudflare). The base's ~614MB"
      echo "!! layer will hit '413 Payload Too Large'. Push to the internal Harbor:"
      echo "!!   REPO=192.168.13.209/defdo/tailwind-builder $0 $TAG $ARCH"
      echo "!! (needs insecure-registries + docker login 192.168.13.209 — see header)"
      ;;
  esac
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
