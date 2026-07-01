# CI Base Image & Internal Registry Runbook

How the Docker images for the Tailwind builder are built and published, and why
the internal-registry workarounds exist. Read this before bumping Elixir/Rust/
Node/Bun versions or debugging a push failure — it captures decisions that were
painful to discover so we don't re-derive them from chat history.

## TL;DR

- **Two images, base + thin worker.** `tailwind-builder` (heavy toolchain,
  ~2.45GB, built rarely) and `tailwind-builder-worker` (`FROM` the base + the
  compiled app, ~20MB delta, built per change).
- **Registry is Harbor, in-cluster, behind Cloudflare.** CF caps uploads (~100MB
  body) → large base layers get **413 Payload Too Large**. The CF proxy **cannot
  be removed** (double-NAT).
- **Push the base internally** (bypass CF) by resolving `hub.defdo.ninja` to the
  Harbor ClusterIP and trusting Harbor's self-signed CA. The worker (thin, 20MB)
  pushes fine through CF.
- **arm64 builds run natively** on an in-cluster arm64 BuildKit (`cloudy-b1`).
  **Do not use QEMU** — we have native arm64 hardware.
- **macOS has no image.** Docker/Podman on macOS is a Linux VM and cannot produce
  a native macOS binary. The macOS target runs a **native worker daemon** on a
  Darwin host with the toolchain installed directly.

## Images

| Image | Repo / Dockerfile | Contents | Size |
| --- | --- | --- | --- |
| Base | `hub.defdo.ninja/defdo/tailwind-builder` — `tailwind_builder/docker/tailwind-builder-v4/Dockerfile` | Elixir/OTP, Node, pnpm, Rust+wasm32, Bun | ~2.45GB (built rarely) |
| Worker | `hub.defdo.ninja/defdo/tailwind-builder-worker` — `tailwind_builder_worker/docker/Dockerfile` | `FROM` base + compiled app | base + ~20MB |

The worker layer is tiny because the toolchain lives in the base. When only
worker code changes, only the ~20MB delta is pushed (base layers are shared and
already in the registry) — that delta is under the CF limit, so the worker
pushes through CF normally. Only the **base** needs the internal-push path.

## Registry facts (Harbor + Cloudflare)

- Public endpoint: `hub.defdo.ninja` → Cloudflare (`104.21.x` / `172.67.x`) →
  Harbor. Harbor project is `defdo`.
- Harbor runs **in the cluster**: `nas-apps/harbor-registry`, ClusterIP
  `10.43.231.228:443`.
- Cloudflare enforces a ~100MB request-body limit (non-Enterprise) → pushing a
  layer larger than that returns **413 Payload Too Large** from Cloudflare.
- The CF proxy is **required** (double-NAT; the origin isn't otherwise
  reachable), so we cannot grey-cloud it away.
- Harbor's TLS cert is **self-signed**: `CN=hub.defdo.ninja, O=defdo`, issuer ==
  subject, **SAN: `hub.defdo.ninja`, `hub.defdo`, `harbor-registry`**. Grab it
  with:
  ```bash
  ssh ubuntu@192.168.13.202 'echo | openssl s_client -connect 10.43.231.228:443 \
    -servername hub.defdo.ninja 2>/dev/null | openssl x509' > harbor-ca.crt
  ```

## Internal push (how the base gets published past the 413)

Resolve `hub.defdo.ninja` to the Harbor ClusterIP and trust the self-signed CA.
Then a push to `hub.defdo.ninja/defdo/...` goes **direct to Harbor** (no CF, no
413) and the cert still verifies (SAN contains `hub.defdo.ninja`). Two variants:

- **amd64 (n150, has Docker):** the Docker daemon's `insecure-registries`
  handles the whole registry incl. the token endpoint. Push to the ClusterIP:
  ```bash
  # /etc/docker/daemon.json on n150 includes {"insecure-registries":["10.43.231.228"]}
  docker login 10.43.231.228 -u "$DEFDO_DOCKER_USERNAME" --password-stdin
  docker tag <img> 10.43.231.228/defdo/tailwind-builder:<tag>
  docker push 10.43.231.228/defdo/tailwind-builder:<tag>
  ```
- **arm64 (in-cluster BuildKit on `cloudy-b1`):** BuildKit does **not** honor
  Docker's `insecure-registries`, and pushing to the bare IP fails cert
  validation (`no IP SANs`). Instead the BuildKit pod has a **`hostAlias`**
  (`hub.defdo.ninja` → `10.43.231.228`) plus the **CA** wired into its
  `buildkitd.toml`, so it pushes to `hub.defdo.ninja` (SAN match + trusted CA).

> Pitfall we hit: BuildKit's per-registry `insecure = true` did **not** cover the
> Harbor **oauth token** endpoint, so the token fetch still failed TLS. The
> hostAlias-to-real-hostname + CA approach avoids `insecure` entirely and is the
> reliable fix.

## Build nodes

| Target | Node | How |
| --- | --- | --- |
| linux/amd64 | `n150` — `ubuntu@192.168.13.202` (cluster node, has Docker) | `docker build` + `docker push` (insecure-registries) |
| linux/arm64 | `cloudy-b1` (in-cluster, 8 vCPU/16Gi) | in-cluster BuildKit Deployment, **native** (no QEMU) |
| darwin/arm64 | mac mini — `defdo@10.0.10.145` | **native worker daemon**, no image |

`radxa` (`ubuntu@10.13.13.13`, arm64, has Docker) is **outside** the cluster and
cannot reach the Harbor ClusterIP, so it is not used for pushing.

## In-cluster arm64 BuildKit

- Manifest: `tailwind_builder_worker/deploy/buildkit-arm64.yaml` (Deployment +
  Service in `defdo-ci`, pinned to `cloudy-b1`, tolerates its `argocd` taint).
- Extra config applied for internal push:
  - ConfigMap `harbor-ca` (`ca.crt` = Harbor's self-signed cert).
  - ConfigMap `buildkit-config` (`buildkitd.toml`):
    ```toml
    [registry."hub.defdo.ninja"]
      ca = ["/etc/buildkit/certs/ca.crt"]
    ```
  - Deployment mounts both, runs `buildkitd --config /etc/buildkit/buildkitd.toml`,
    and sets `hostAliases: hub.defdo.ninja -> 10.43.231.228`.
- Woodpecker secret `buildkit_host_arm64` →
  `tcp://buildkit-arm64.defdo-ci.svc.cluster.local:1234`.
  `buildkit_host_amd64` → the n150 BuildKit endpoint.

Verify health:
```bash
kubectl -n defdo-ci exec deploy/buildkit-arm64 -- buildctl debug workers   # linux/arm64
kubectl -n defdo-ci exec deploy/buildkit-arm64 -- getent hosts hub.defdo.ninja  # 10.43.231.228
```

## Rebuild the base (after an Elixir/Rust/Node/Bun bump)

Sources of truth for versions:

- `tailwind_builder/docker/tailwind-builder-v4/Dockerfile`: `FROM elixir:<X>-slim`
  and the `ARG NODE_VERSION / RUST_VERSION / BUN_VERSION / PNPM_VERSION`.
- `tailwind_builder/lib/defdo/tailwind_builder/dependencies.ex`:
  `@required_rust_targets` (currently `wasm32-wasip1-threads`) and
  `@required_tools`.

Then, from a machine with the repos synced to the build nodes:

```bash
# 1. amd64 (n150): build + push internally
ssh ubuntu@192.168.13.202
  docker build -f tailwind_builder/docker/tailwind-builder-v4/Dockerfile \
    -t 10.43.231.228/defdo/tailwind-builder:<ver>-amd64 tailwind_builder
  docker push 10.43.231.228/defdo/tailwind-builder:<ver>-amd64

# 2. arm64 (native on b1 via buildx remote from n150)
  docker buildx create --name b1remote --driver remote tcp://10.43.175.235:1234 --use
  docker login hub.defdo.ninja -u "$DEFDO_DOCKER_USERNAME" --password-stdin   # via CF (small, ok)
  docker buildx build --platform linux/arm64 \
    -f tailwind_builder/docker/tailwind-builder-v4/Dockerfile \
    -t hub.defdo.ninja/defdo/tailwind-builder:<ver>-arm64 --push tailwind_builder

# 3. multi-arch manifest -> latest / <ver>
  docker manifest create --insecure hub.defdo.ninja/defdo/tailwind-builder:latest \
    hub.defdo.ninja/defdo/tailwind-builder:<ver>-amd64 \
    hub.defdo.ninja/defdo/tailwind-builder:<ver>-arm64
  docker manifest push --insecure hub.defdo.ninja/defdo/tailwind-builder:latest
```

Credentials come from `load_hub_defdo` (`DEFDO_DOCKER_USERNAME` /
`DEFDO_DOCKER_PASSWORD`) in `~/.dotfiles/secret.defdo.zsh`.

## Non-obvious decisions (do not "optimize" these away)

- **`wasm32-wasip1-threads` is required.** The workspace build runs the oxide
  crate's full `build` = `build:platform && build:wasm`; `build:wasm` targets
  `wasm32-wasip1-threads`. Removing it breaks the build with
  `can't find crate for core/std`. (Upstream's release workflow sidesteps this by
  building oxide per-target with `build:platform` only, but our flow runs the
  workspace build.)
- **`elixir:<X>-slim`, not Alpine.** Alpine is musl; building oxide there yields
  musl binaries, which mismatch our `linux-x64`/`linux-arm64` (gnu) targets. Slim
  is Debian + glibc and ~2GB smaller than the full image.
- **The ~2.45GB base is real toolchain, not junk.** `docker images` reports the
  **uncompressed** size; the compressed transfer is ~1GB. Docker Hub's ~130MB for
  `elixir-slim` is that base image alone, compressed. apt/bun-zip/rustup-downloads
  /npm-cache are already cleaned.
- **Docker Hardened Images (distroless) don't fit.** The worker is a *build*
  environment (needs a shell + package manager + the toolchain at runtime); a
  distroless base can't host that.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `413 Payload Too Large` (Cloudflare) on push | layer > CF body limit | push the base internally (see above); worker delta is small enough for CF |
| `tls: ... doesn't contain any IP SANs` | pushed to the bare ClusterIP | push to `hub.defdo.ninja` with hostAlias→ClusterIP + CA trust |
| `x509: certificate signed by unknown authority` | Harbor's self-signed CA not trusted | mount `harbor-ca` and reference it in `buildkitd.toml` / trust it on the host |
| arm64 build is extremely slow | QEMU emulation | build natively on `cloudy-b1` BuildKit instead |
| `can't find crate for core/std` | wasm32 target missing | keep `rustup target add wasm32-wasip1-threads` in the base |
