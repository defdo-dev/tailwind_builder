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
