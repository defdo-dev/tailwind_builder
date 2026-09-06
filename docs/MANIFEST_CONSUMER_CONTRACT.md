# Manifest Consumer Contract (tailwind_compiler)

This document defines how an external consumer — primarily `tailwind_compiler` —
resolves a Tailwind CLI binary from a `tailwind_builder` release.

A minimal, deterministic example is published alongside this file:
[`sample_manifest.v4.2.2-rc1.json`](./sample_manifest.v4.2.2-rc1.json). It mirrors
the shape of a real published `manifest.json`; the `provenance.hostname` is a
placeholder and timestamps are zeroed for determinism.

## Rule: consume `manifest.json`, never hard-code binary URLs

The consumer MUST resolve binaries through the per-channel `manifest.json`. It
MUST NOT hard-code artifact URLs, `latest`, or version-specific binary paths.

For release channel `<channel>` and prefix `<prefix>` under the public storage
base URL, the metadata lives at:

```
<storage_base_url>/<prefix>/<channel>/manifest.json
<storage_base_url>/<prefix>/<channel>/sha256sums.txt
```

For the proven `v4.2.2-rc1` release that is:

```
https://storage.defdo.de/tailwind_cli_daisyui/v4.2.2-rc1/manifest.json
https://storage.defdo.de/tailwind_cli_daisyui/v4.2.2-rc1/sha256sums.txt
```

## Resolution algorithm

1. Fetch `manifest.json`.
2. Confirm `manifest_schema_version` is supported (currently `1`).
3. Validate the exact CLI version against `tailwind_cli_version` (do not assume
   it equals `tailwind_version` in general; for this release both are `4.2.2`).
4. Select the artifact whose `target_key` matches the host target (e.g.
   `macos-arm64`). `target_key` is the canonical identifier from
   `Defdo.TailwindBuilder.Core.Targets`; `build_target` is the toolchain triple
   (e.g. `aarch64-apple-darwin`); `artifact_name` is the published filename.
5. Download the artifact from its `storage_url`.
6. Compute the sha256 of the downloaded bytes and compare it to the artifact's
   `checksum_sha256`. Reject on mismatch.
7. Optionally cross-check against `sha256sums.txt`, which lists
   `"<sha256>  <artifact_name>"` per line and must agree with the manifest.
8. Mark the binary executable and cache it keyed by
   `tailwind_cli_version` + `target_key` + `checksum_sha256`.

## Field reference (per artifact)

| Field | Meaning |
| --- | --- |
| `target_key` | Canonical host/target identifier; the consumer selects by this. |
| `build_target` | Toolchain triple used to build the artifact. |
| `artifact_name` | Published filename. |
| `storage_url` | Absolute public download URL. |
| `checksum_sha256` | Lowercase hex sha256 of the artifact bytes. |
| `size_bytes` | Exact byte size of the artifact. |
| `built_at` | ISO-8601 build timestamp. |

## Integrity guarantees

- `manifest.json` and `sha256sums.txt` are published only after the binary is
  present in storage. A consumer that finds `manifest.json` can rely on the
  referenced artifacts existing.
- `checksum_sha256` in `manifest.json` equals the corresponding entry in
  `sha256sums.txt` and the sha256 of the bytes served at `storage_url`. This was
  verified end-to-end for `v4.2.2-rc1` (downloaded artifact sha256
  `6c426808102ce8367a42d159f777ff953f209c49498ceadc336ef1b5aac03070`).

## Release catalog (channel discovery)

A consumer that wants *a channel* — the newest production release — rather than
a pinned version reads the release catalog published by
`Deployer.publish_release_catalog/1`:

```
<storage_base_url>/tailwind_cli_daisyui/releases.json
```

It picks the newest entry with `"status": "productivo"`, takes its
`tailwind_version`, and then follows the resolution algorithm above unchanged.

Catalog shape (quoted from the `defdo_theme_hub` 0.8.0 configuration reference,
which consumes it through `RuntimeManager.published_versions/1`):

```json
{
  "versions": [
    {
      "version": "4.3.3-daisyui",
      "tailwind_version": "4.3.3",
      "flavor": "daisyui",
      "status": "productivo",
      "published_at": "2026-07-29T01:32:49Z",
      "url": "https://storage.defdo.de/tailwind_cli_daisyui/v$version/tailwindcss-$target",
      "metadata": { "daisyui_version": "5.7.4" },
      "hash": {
        "linux-x64":   { "sha256": "<64 hex>" },
        "linux-arm64": { "sha256": "<64 hex>" },
        "macos-arm64": { "sha256": "<64 hex>" }
      }
    },
    {
      "version": "4.3.4-rc1-daisyui",
      "tailwind_version": "4.3.4-rc1",
      "flavor": "daisyui",
      "status": "in_progress",
      "published_at": "2026-09-05T00:00:00Z",
      "url": "https://storage.defdo.de/tailwind_cli_daisyui_ci_canary/v$version/tailwindcss-$target",
      "hash": {}
    }
  ]
}
```

Rules:

- `$version` and `$target` in `url` are placeholders substituted by the
  consumer at install time: `$version` is the **upstream** Tailwind version
  (`tailwind_version`), and `$target` is the Theme Hub target name — the
  canonical `target_key` used by this builder, except Windows, which Theme Hub
  names `windows-x64.exe`.
- `hash[target].sha256` is required for every `productivo` target
  (`hash[target].md5` is optional). An `in_progress` entry is visible but may
  omit hashes (`"hash": {}`).
