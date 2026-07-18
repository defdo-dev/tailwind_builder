# Changelog

## [Unreleased]

## [0.2.23]

> Toolchain/CI release — the Elixir library is unchanged from 0.2.21. Supersedes
> 0.2.22, whose base build failed at push (misconfigured registry target); the
> WASI SDK fix is unchanged, only the push path differs.

### Fixed
- Base toolchain image (`docker/tailwind-builder-v4/Dockerfile`): install the
  WASI SDK (clang + wasm-ld + wasi sysroot) so napi-rs can build
  `@tailwindcss/oxide`'s `wasm32-wasip1-threads` artifact. The image had the
  Rust target (`rustup target add`) but not the C toolchain it needs, so the
  workspace build (`turbo build`) failed at oxide's `build:wasm` step and the
  standalone `dist/` was never produced — every cold-cache build died at deploy
  `find_binaries` (`dist_directory_not_found`). Warm turbo cache had been
  masking it. Keeps wasm buildable for a future in-browser (CMS/CodeMirror)
  Tailwind compile carrying custom plugins.

### Changed
- Base-image CI (`.woodpecker/docker-image.yml`): documented that the push goes
  to `hub.defdo.ninja` by NAME. In-cluster CoreDNS already rewrites that name to
  the internal traefik LB (not Cloudflare), so the old "Cloudflare 413s the
  ~614MB layer" note is stale — traefik streams the push with no body limit
  (verified: a 300MB test layer pushes clean). Pushing by the ClusterIP instead
  fails TLS (Harbor's cert has DNS SANs but no IP SAN, and buildkit's
  `registry.insecure` does not cover the `/service/token` fetch), which is why
  0.2.22's ClusterIP attempt was reverted.

## [0.2.21]

### Changed
- Internal refactor to resolve all `mix credo --strict` findings (89: 1 warning,
  36 refactoring, 34 readability, 18 design) across 30 lib modules. Refactor-only,
  no behavior change: extracted private helpers, reduced nesting/complexity, and
  renamed predicate functions to drop the `is_` prefix
  (`technically_possible?/2`, `executable?/1`) — the old names
  (`is_technically_possible?/2`, `is_executable?/1`) are preserved as
  `defdelegate`, so the public API is unchanged. Compile `--warnings-as-errors`
  clean, 288 tests still green.

## [0.2.20]

### Changed
- Replace the third-party `req_s3` with the internal `defdo_s3` (`Defdo.S3.attach/2`,
  drop-in for `ReqS3.attach/2`) for R2/S3 uploads in `Deployer`. This removes an
  external dependency we do not control from the tree and lets us govern the `req`
  version constraint ourselves (`defdo_s3` already allows `req ~> 0.6`). Combined
  with 0.2.19's `req ~> 0.6` bump, this clears the `req` DoS advisory
  (CVE-2026-49755, HIGH) for consumers.

### Fixed
- Hex publish CI: run `.woodpecker/hex-publish.yml` on the public `elixir:1.19-slim`
  image instead of the internal `tailwind-builder:latest` toolchain image. `:latest`
  is only rebuilt on toolchain-change tags and can be evicted from the registry,
  which broke code-tag publishes (`exec: "...tailwind-builder:latest": no such
  file`). Publishing needs only Elixir + Mix + Hex, so it no longer depends on that
  image. (The binary build pipelines still require the toolchain image.)

### Added
- Pre-commit hook (`.githooks/pre-commit`, install with `mix hooks.install`):
  `mix format --check-formatted` on staged files + `mix credo diff` gating only
  NEW issues since HEAD (pre-existing debt does not block). Adds `credo` (dev/test)
  and a `mix check` alias for the full-tree gate.

## [0.2.19]

### Changed
- Bump `req` to `~> 0.6` (0.6.3) and `req_s3` to `~> 0.2.4`. This clears the
  `req` 0.5.18 decompression-bomb DoS advisory (CVE-2026-49755, HIGH) for
  consumers — the previous `~> 0.5.15` pin held them below the fixed 0.6.x line.

## [0.2.18]

### Fixed
- Plugin patcher escapes scoped package names (e.g.
  `@midudev/tailwind-animations`) before embedding them in the standalone
  `index.ts` JS regex literals. Previously the unescaped `/` terminated the
  regex early and produced a corrupt patch, so scoped plugins could not be baked
  in. String-literal spots (`require(...)`, import map, `id === '...'`) keep the
  raw package name.

### Added
- Plugin functional probes for `tailwindcss-animate` and `tw-animate-css`.
  Probes now declare how a plugin loads: JS plugins use `@plugin "pkg"`,
  CSS-first plugins (`tw-animate-css`) use `@import "pkg"`. The probe stays
  fail-closed — a plugin that installs but does not generate its marker fails the
  release. Note: the `tw-animate-css` CSS-first path has not yet been proven
  against a full real build; the first build that includes it is the proof.

## [0.2.17]

### Changed
- Hex publishing moved from GitHub Actions to Woodpecker CI
  (`.woodpecker/hex-publish.yml`, triggered on tag). Uses the global Woodpecker
  `hex_api_key` / `hex_org_token` secrets. Removed the unused
  `.github/workflows/publish_hex.yml`. First version actually published to the
  private `defdo` Hex org.

## [0.2.16]

### Added
- Hex packaging: the library now publishes to the private `defdo` organization on
  tag (package metadata, `VERSION` file, docs, `.github/workflows/publish_hex.yml`).
  Consumers can depend on it via Hex (`{:tailwind_builder, "~> 0.2", organization:
  "defdo"}`) instead of a local path.

## [0.2.15]

### Changed
- Removed the unused private `asdf_exec/2` helper (dead code). This clears a
  `mix compile --warnings-as-errors` warning that broke the stricter compile
  gate of path-dependency consumers (e.g. `tailwind_builder_hub`).

> Note: CHANGELOG entries for 0.2.1–0.2.14 were not backfilled; releases in that
> range were tag-driven without changelog updates.

## [0.2.0]

### Added
- Manifest includes `release_fingerprint` per artifact tying each published file to its frozen recipe.
- Manifest preserves per-file `plugin_set` evidence for downstream promote gates.
- Deployer merge filters stale artifacts whose fingerprint doesn't match the incoming recipe.

### Changed
- Release resolves `plugin_key` from the spec map so explicit key tracking survives the full pipeline.

### Fixed
- Fixed plugin import resolution in standalone builds.

## [0.1.0]

## 0.1.0

- Supports for download source and patch the content.

> Requires `npm` to build and compile.
> Interested in see how it works see the [workflows](https://github.com/tailwindlabs/tailwindcss/tree/master/.github/workflows) in which this is inspired.
