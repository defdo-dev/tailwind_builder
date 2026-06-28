# Docker Toolchain Image

The `docker/tailwind-builder-v4/Dockerfile` provides a reproducible Linux build
environment for Tailwind CLI standalone binaries.  It contains all required tools
but no project source — mount the repo at `/workspace` at runtime.

## Tool versions (pinned)

| Tool | Version | Source |
|---|---|---|
| Elixir | 1.18 (OTP 27) | base image `elixir:1.18` |
| Node | 22.6.0 | nodejs.org binary |
| pnpm | 9.15.9 | npm |
| Rust / cargo | 1.90.0 | rustup |
| wasm32-wasip1-threads | (with Rust) | rustup target |
| Bun | 1.2.23 | GitHub release |

Versions are ARG-driven — override at build time with `--build-arg`:

```bash
docker build \
  -f docker/tailwind-builder-v4/Dockerfile \
  --build-arg NODE_VERSION=22.6.0 \
  --build-arg RUST_VERSION=1.90.0 \
  --build-arg BUN_VERSION=1.2.23 \
  -t hub.defdo.ninja/defdo/tailwind-builder:0.1.0 \
  .
```

## Build the image

```bash
make image-build
```

or directly:

```bash
docker build \
  -f docker/tailwind-builder-v4/Dockerfile \
  -t hub.defdo.ninja/defdo/tailwind-builder:0.1.0 \
  .
```

## Verify tool versions

```bash
make image-verify
```

Expected output (versions may differ if ARGs are overridden):

```
Erlang/OTP 27 [erts-...] ...
Elixir 1.18.x ...
v22.6.0
9.15.9
rustc 1.90.0 ...
1.2.23
```

## Local docker run — canary release

Set R2 credentials in the shell **before** running (values are not printed):

```bash
export R2_ACCESS_KEY_ID=...
export R2_SECRET_ACCESS_KEY=...
export R2_HOST=...            # e.g. <acct>.r2.cloudflarestorage.com
export R2_REGION=auto         # optional, defaults to auto
```

Then:

```bash
make docker-canary
```

or directly:

```bash
docker run --rm \
  -w /workspace \
  -v "$PWD":/workspace \
  -e R2_ACCESS_KEY_ID \
  -e R2_SECRET_ACCESS_KEY \
  -e R2_HOST \
  -e R2_REGION \
  hub.defdo.ninja/defdo/tailwind-builder:0.1.0 \
  sh -c 'mix deps.get && mix tailwind.release \
    --version 4.2.2 \
    --channel v4.2.2-rc1-linux-canary \
    --config-provider testing \
    --bucket defdo \
    --prefix tailwind_cli_daisyui_ci_canary \
    --storage-base-url https://storage.defdo.de \
    --plugin daisyui_v5 \
    --smoke-test \
    --verify-upload \
    --verify-smoke-test \
    --overwrite-policy fail'
```

Note: `-e KEY` (without `=VALUE`) forwards the variable from the shell environment
without printing the value. Do not use `-e KEY=VALUE` for secrets in scripts.

## Interactive shell

```bash
make docker-shell
```

Drops into bash with the repo mounted at `/workspace`.

## Expected canary output

On success:

- Binary built: `tailwindcss-linux-x64`
- Smoke test: `passed`
- Upload: verified against R2 public URL
- Manifest published: `https://storage.defdo.de/tailwind_cli_daisyui_ci_canary/v4.2.2-rc1-linux-canary/manifest.json`
- Checksums published: `https://storage.defdo.de/tailwind_cli_daisyui_ci_canary/v4.2.2-rc1-linux-canary/sha256sums.txt`

## Woodpecker pipeline

`.woodpecker/canary-linux.yml` automates the canary release on push to `canary/*`
branches or manual trigger.

### Required secrets (set once in Woodpecker project settings)

| Secret name | Description |
|---|---|
| `r2_access_key_id` | Cloudflare R2 access key ID |
| `r2_secret_access_key` | Cloudflare R2 secret access key |
| `r2_host` | R2 endpoint host (no `https://` prefix) |
| `r2_region` | R2 region, usually `auto` |

Secrets are injected as environment variables and are never echoed to build logs.

### Pipeline steps

1. `test` — `mix deps.get && mix test` inside the toolchain image
2. `release-canary-linux` — `mix tailwind.release ...` with R2 secrets

### Runner requirements

- Woodpecker agent with Docker support
- `platform: linux/amd64` label (set in the pipeline YAML)
- Image `hub.defdo.ninja/defdo/tailwind-builder:0.1.0` must be available (build and push before first run)

## Limitations

- **Linux only** — the image targets `linux/amd64`. Cross-compilation to
  `linux-arm64`, `macos-arm64`, `windows-x64`, etc., requires native hosts.
- **Source not baked in** — the image is toolchain-only; the repo is mounted or
  cloned at runtime. This keeps the image small and the source separate.
- **Not a production overwrite** — canary uses prefix `tailwind_cli_daisyui_ci_canary`
  and channel `v4.2.2-rc1-linux-canary`. Production prefix `tailwind_cli_daisyui` is
  never touched by this pipeline.
