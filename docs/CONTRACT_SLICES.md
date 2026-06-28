# Tailwind Builder Contract Slices

This document defines the bounded slices for `tailwind_builder`, the shared
artifact producer in the workspace.

Use this file before changing `tailwind_builder` from Kimi, DeepSeek, Codex, or
any other implementation agent.

## Package Boundary

`tailwind_builder` owns:

- Tailwind source download and checksum validation.
- Plugin patching for the pinned release flow.
- Target normalization and artifact naming.
- Local build orchestration.
- Artifact publication and manifest generation.

`tailwind_builder` does not own:

- worker discovery or heartbeats;
- job scheduling or queue state;
- operator UI;
- auth or node registration policy.

Those concerns belong to `tailwind_builder_hub` or `tailwind_builder_worker`.

## Slice Status

| Slice | Status | Source of truth |
| --- | --- | --- |
| Canonical target mapping | implemented | `Defdo.TailwindBuilder.Core.Targets` |
| Release orchestration | implemented | `Defdo.TailwindBuilder.Release` |
| Artifact publication | implemented, still tightening | `Defdo.TailwindBuilder.Deployer` |
| Remote execution entrypoints | partial | `Defdo.TailwindBuilder.RemoteBuilder`, `Defdo.TailwindBuilder.GitHubBuilder` |
| Hub or worker runtime state | out of scope | `tailwind_builder_hub`, `tailwind_builder_worker` |

## Slice 1: Canonical Target Mapping

Status: `implemented`

Owner:

- `Defdo.TailwindBuilder.Core.Targets`
- `Defdo.TailwindBuilder.Core.ArchitectureMatrix`

Purpose:

- Normalize every target into one canonical `target_key`.
- Derive the toolchain `build_target`.
- Derive the published `artifact_name`.

Required contract:

- UI and manifests speak in `target_key`.
- Builders and toolchains speak in `build_target`.
- Published files speak in `artifact_name`.

Inputs:

- host architecture;
- requested `target_key`;
- release version when compatibility matters.

Outputs:

- normalized target metadata;
- supported target list;
- deterministic artifact naming.

Non-goals:

- no worker availability state;
- no scheduler policy;
- no storage upload.

Implementation rules:

- Never invent new target strings in downstream code.
- Never use raw `uname`, Rust triples, or UI labels as the primary identifier.
- Every new target must update tests and manifest expectations.

## Slice 2: Release Orchestration

Status: `implemented`

Owner:

- `Defdo.TailwindBuilder.Release`
- `mix tailwind.release`

Purpose:

- Execute the pinned `v4.2.2-rc1` flow for Tailwind `4.2.2` and DaisyUI
  `5.5.19`.

Required contract:

- accept explicit release inputs;
- download source;
- apply plugins;
- build artifacts;
- optionally smoke test;
- generate manifest metadata;
- hand deploy inputs to the deployer.

Stable inbound contract:

```elixir
[
  version: "4.2.2",
  release_channel: "v4.2.2-rc1",
  source_path: "/tmp/path",
  destination: :r2,
  bucket: "defdo",
  prefix: "tailwind_cli_daisyui",
  storage_base_url: "https://storage.defdo.de",
  plugins: ["daisyui_v5"],
  config_provider: Defdo.TailwindBuilder.ConfigProviders.TestingConfigProvider
]
```

Stable outbound contract:

- release metadata for the channel;
- plugin set used for the build;
- deploy result with manifest and checksums.

Non-goals:

- no long-lived job storage;
- no worker leases;
- no dashboard-specific formatting.

Implementation rules:

- Keep the release flow pinned. Do not switch to `latest`.
- Keep orchestration here instead of moving it into Hub or Worker code.
- Extend the manifest shape here only when `tailwind_compiler` or deploy
  verification needs it.

## Slice 3: Artifact Publication

Status: `implemented, still tightening`

Owner:

- `Defdo.TailwindBuilder.Deployer`

Purpose:

- Publish built binaries and metadata to the selected storage target.

Current evidence:

- deployer test coverage exists;
- release tests assert manifest and checksum generation;
- R2-style configuration is already used by the release task;
- app config key renamed from `:aws` to `:storage` (deployer `storage_req/0`,
  release `maybe_put_runtime_config/2`, mix task `maybe_put_storage_config/1`);
- `R2_HOST` normalization implemented: `normalize_storage_host/1` strips
  `https://` / `http://` prefixes and trailing slashes (Deployer
  `lib/defdo/tailwind_builder/deployer.ex:779`, tested in
  `test/defdo/tailwind_builder/deployer_test.exs`);
- `mix tailwind.release` reuses `Deployer.normalize_storage_host/1` instead of a
  local duplicate, so host normalization has a single source of truth.

Post-upload verification contract (implemented):

- Hook: `Defdo.TailwindBuilder.Deployer.verify_uploaded_artifacts/2`.
- Accepted options:
  - `:storage_base_url` (required to build artifact URLs);
  - `:verification_fetcher` (`(url -> {:ok, binary} | {:error, term})`,
    defaults to a Req-based fetcher, injectable for tests);
  - `:verification_timeout` (per-request ms, default `30_000`).
- Each result: `%{artifact_name, storage_url, status, expected_sha256,
  actual_sha256, error}` where `status` is `:verified`, `:mismatch`, or
  `:fetch_failed`.
- Return: `{:ok, %{verified, failed, results}}` or
  `{:error, {:verification_failed, %{verified, failed, results}}}`.
- When `:verify_upload` is `true`, the `deploy/1` pipeline runs the hook after
  upload and aborts before checksum files, manifest, and metadata are published
  on any failed artifact.
- Public release path wiring: `Defdo.TailwindBuilder.Release.run/1` accepts and
  forwards `:verify_upload`, `:verification_fetcher`, and `:verification_timeout`
  to `Deployer.deploy/1` (defaults `verify_upload: false`). `mix tailwind.release`
  exposes `--verify-upload`. Because the deployer gates metadata publication on
  verification, metadata is not published before verification succeeds.
- Smoke-test verification (implemented): with `:verify_smoke_test` true, each
  checksum-verified download is written to a temp file and smoke tested
  (`:verification_smoke_tester` injectable, defaults to `smoke_test_binary/2`).
  A smoke failure sets the result `status` to `:smoke_failed` (counted as a
  failure), so metadata publication is aborted. `mix tailwind.release` exposes
  `--verify-smoke-test`.
- Covered by `test/defdo/tailwind_builder/deployer_test.exs`
  (`verify_uploaded_artifacts/2` and `verify_uploaded_artifacts/2 with smoke
  test` describe blocks),
  `test/defdo/tailwind_builder/release_test.exs` (forwards verify options to the
  deployer), and `test/mix/tasks/tailwind/release_test.exs` (`--verify-upload`
  reaches `release_opts`).

Manifest schema (implemented):

- `generate_deployment_manifest/3` emits `manifest_schema_version` (currently
  `1`), separate `tailwind_version`, `tailwind_cli_version`, and
  `release_channel`, and a `provenance` map.
- Per-artifact fields: `target_key`, `build_target`, `artifact_name`,
  `storage_url`, `checksum_sha256`, `size_bytes`, and `built_at` (plus
  `filename`, `size_mb`, `architecture`, `remote_key`). `build_target` comes from
  `Core.Targets`; `target_key` is canonical.
- `provenance` fields observable locally: `hostname`, `os`, `arch`,
  `elixir_version`, `otp_release`, `node_version`, `rust_version`, `bun_version`,
  `pnpm_version`, `source_checksum` (from opts), and `git_sha`. Absent tools
  resolve to `nil` instead of failing the manifest.
- Covered by `deployer_test.exs` (`manifest schema and provenance` describe
  block).

Overwrite policy and dry run (implemented):

- `Deployer.resolve_overwrite_plan/4` resolves `:dry_run | :upload | :republish`
  from the `:overwrite_policy` option and an injectable `:existence_checker`
  (defaults to a Req `HEAD`):
  - `:overwrite` (default) — always `:upload`;
  - `:fail` — `:upload` only when no target artifact exists, otherwise
    `{:error, {:artifacts_exist, names}}`;
  - `:promote_only` — `:republish` only when every target artifact exists,
    otherwise `{:error, {:artifacts_missing, names}}`.
- `:dry_run` runs all local steps (manifest + checksums from local files) and
  uploads nothing: no binary upload, no verify, no metadata publish
  (`auxiliary_files: []`). `:promote_only` regenerates and republishes metadata
  from local files without re-uploading binaries.
- `Release.run/1` forwards `:dry_run`, `:overwrite_policy`,
  `:tailwind_version`, `:tailwind_cli_version`, `:source_checksum`, and
  `:verify_smoke_test`. `mix tailwind.release` exposes `--dry-run` and
  `--overwrite-policy fail|overwrite|promote_only`.
- Covered by `deployer_test.exs` (`resolve_overwrite_plan/4` and `deploy/1 dry
  run` describe blocks, including deterministic reruns) and
  `test/mix/tasks/tailwind/release_test.exs` (`--dry-run`/`--overwrite-policy`).

Upload timeout (implemented):

- `Deployer.resolve_upload_timeout/1` resolves the storage upload receive timeout
  (ms) from `:tailwind_builder, :storage` `:upload_timeout`, defaulting to
  `300_000`. `storage_req/0` passes it as `Req.new(receive_timeout: ...)`. This
  prevents spurious `%Req.TransportError{reason: :timeout}` on large binary PUTs
  over a slow link (the object had uploaded; only the response read timed out).
  Covered by `deployer_test.exs` (`resolve_upload_timeout/1` describe block).

Real publish evidence (v4.2.2-rc1, macos-arm64):

- Real upload to R2 / `https://storage.defdo.de` succeeded for
  `tailwindcss-macos-arm64`.
- Public `manifest.json` and `sha256sums.txt` are published and agree with the
  artifact bytes (sha256
  `6c426808102ce8367a42d159f777ff953f209c49498ceadc336ef1b5aac03070`).
- External (curl/jq/sha256) consumer validation passed without reusing deployer
  functions; the downloaded artifact also passed a daisyUI smoke test.
- Consumer contract documented in `docs/MANIFEST_CONSUMER_CONTRACT.md` with a
  deterministic sample at `docs/sample_manifest.v4.2.2-rc1.json`.
- Scope of proof: a single host target (`macos-arm64`). The deployer's own
  `--verify-upload` + `--verify-smoke-test` pipeline against real R2 was proven
  end-to-end via a canary run (prefix `tailwind_cli_daisyui_canary`, channel
  `v4.2.2-rc1-verify-canary`): real upload → deployer HEAD → deployer public
  fetch → checksum verified (`820b187d…`) → smoke `:passed` → metadata published
  only after verification (`manifest.json` + `sha256sums.txt`, HTTP 200).
  Production prefix (`tailwind_cli_daisyui/v4.2.2-rc1`) was not touched.

Open contract work:

- promotion across channels (Phase 3) still builds on `:promote_only` but is not
  implemented (copy/regenerate stable-channel URLs, rollback).

Non-goals:

- no worker registration;
- no target discovery;
- no auth tokens.

Implementation rules:

- Keep provider details inside deployer code.
- Keep manifest fields deterministic and explicit.
- If behavior is not verified by tests yet, mark it pending in docs.

## Slice 4: Remote Execution Boundary

Status: `implemented (MVP — one host, SSH)`

Owner:

- `Defdo.TailwindBuilder.HostCapability` — local/remote capability probe
- `Defdo.TailwindBuilder.Remote.SSHExecutor` — thin SSH wrapper
- `Defdo.TailwindBuilder.Remote.Release` — remote release orchestration
- `Defdo.TailwindBuilder.Remote.MissingTargets` — pure target-gap report
- `mix tailwind.release.remote` — CLI entrypoint

Purpose:

- Detect remote host build capabilities over SSH (single probe command, KEY=VALUE output).
- Run the existing `mix tailwind.release` flow on one remote host via SSH.
- Capture stdout, exit status, artifact metadata, and verification result.
- Write a local JSON report (`schema_version: 1`) suitable for Hub consumption.
- Report missing targets (desired vs discovered vs published) as structured data.

Capability detection contract:

- One SSH call runs the embedded shell probe script and returns KEY=VALUE pairs.
- Output always includes: `hostname`, `os`, `arch`, `elixir_version`, `otp_release`,
  `node_version`, `pnpm_version`, `rust_version`, `bun_version`, `git_sha`.
- Missing tools are reported as `"missing"` (nilified), never as crashes.
- `target_key`, `build_target`, `artifact_name` come from `Defdo.TailwindBuilder.Core.Targets`
  and are `nil` for unsupported platforms.
- `build_capable: false` when any required v4 tool is missing or target is unsupported.
- Required v4 tools: `node`, `pnpm`, `rustc`, `bun`.
- Injectable via `:runner` option for isolated tests.

Remote release command shape:

```bash
mix tailwind.release.remote \
  --host builder.example.com \
  --workdir /home/build/tailwind_builder \
  --version 4.2.2 \
  --channel v4.2.2-rc1 \
  --config-provider testing \
  --bucket defdo \
  --prefix tailwind_cli_daisyui \
  --storage-base-url https://storage.defdo.de \
  --plugin daisyui_v5 \
  --smoke-test \
  --verify-upload \
  --verify-smoke-test \
  --overwrite-policy fail \
  --report-path ./tmp/tailwind-release-report.json
```

R2 credentials: sourced from `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_HOST`,
`R2_REGION` on the local machine and passed as shell env-var assignments in the SSH
command. Values are never logged — `SSHExecutor.redact_secrets/2` produces a
`[REDACTED]` form for all log output.

Report JSON contract (`schema_version: 1`):

```json
{
  "schema_version": 1,
  "executed_at": "<iso8601>",
  "release_channel": "v4.2.2-rc1",
  "tailwind_version": "4.2.2",
  "tailwind_cli_version": "4.2.2",
  "plugin": "daisyui_v5",
  "remote": {"host": "...", "workdir": "...", "hostname": "...", "os": "...", "arch": "..."},
  "capability": {
    "target_key": "linux-x64",
    "build_target": "x86_64-unknown-linux-gnu",
    "artifact_name": "tailwindcss-linux-x64",
    "build_capable": true,
    "missing_tools": [],
    "elixir_version": "...", "otp_release": "...",
    "node_version": "...", "rust_version": "...", "bun_version": "...", "pnpm_version": "...",
    "git_sha": "..."
  },
  "status": "published | failed | not_buildable",
  "artifact": {"target_key": "...", "storage_url": "...", "checksum_sha256": "...", ...},
  "verification": {"upload_verified": false, "smoke_tested_download": false, "status": "skipped|passed"},
  "logs": {"stdout_path": "...", "stderr_path": null, "exit_status": 0},
  "missing_targets": {"published": [...], "buildable_now": [...], "missing": [...], "failed": [...]}
}
```

`status` values:

- `"published"` — SSH exited 0, manifest fetched (or attempted) successfully.
- `"failed"` — SSH exited non-zero; logs preserved in `stdout_path`.
- `"not_buildable"` — capability probe found missing tools or unsupported target; no SSH release attempted.

MissingTargets helper contract:

- `MissingTargets.report(desired:, published:, buildable:, failed:)` — pure function.
- Normalizes all inputs through `Core.Targets.normalize/1` before comparison.
- Returns `%{published: [], buildable_now: [], missing: [], failed: []}`.
- `MissingTargets.published_from_manifest/1` extracts `target_key` list from a manifest map.
- `MissingTargets.all_canonical_targets/0` returns the full canonical target list.

Test coverage:

- `test/defdo/tailwind_builder/host_capability_test.exs` — capability detection (injectable runner),
  target resolution for all supported platforms, missing-tools reporting, error propagation.
- `test/defdo/tailwind_builder/remote/ssh_executor_test.exs` — run/3 with injectable runner,
  `redact_secrets/2`, `build_ssh_flags/2`.
- `test/defdo/tailwind_builder/remote/missing_targets_test.exs` — all bucket logic, manifest extraction,
  alias normalization.
- `test/defdo/tailwind_builder/remote/release_test.exs` — published/failed/not_buildable reports,
  command building with redaction, all required JSON keys, file writes.
- `test/mix/tasks/tailwind/release/remote_test.exs` — option parsing, success/failure output,
  Mix.Error on non-zero exit.
- No real SSH host required for the automated test suite.

Open items:

- Manual SSH smoke against a real remote host is pending (no remote Linux builder available at
  publish time). Automated tests cover the adapter via test doubles.
- `artifact` in the report is fetched from the published `manifest.json` after a successful SSH
  run; when the manifest fetch fails (network, not yet published), `artifact` is `nil` in the report.
- Full target matrix multi-host orchestration is out of scope for this milestone.

Rules:

- Treat these modules as adapter boundaries, not as the control plane.
- Do not add worker inventory, leases, or operator state here.
- Do not let remote adapters become the source of truth for target availability.

Next safe milestone:

- one SSH-driven remote release command that returns a structured JSON report
  without introducing hub scheduling.

## Agent Rules

- Change one slice at a time.
- Add focused tests for any behavioral change.
- Do not move hub or worker responsibilities into this package to "move faster".
- When a proposed contract becomes implemented, update this file and cite the
  real module or test surface that proves it.
