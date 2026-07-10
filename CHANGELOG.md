# Changelog

## [Unreleased]

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
