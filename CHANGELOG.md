# Changelog

## [Unreleased]

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
