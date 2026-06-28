# Tailwind Builder Release Work Plan

## Goal

Turn `tailwind_builder` into the reliable artifact producer for Defdo Tailwind CLI binaries, starting with:

- `tailwindcss 4.2.2`
- `@tailwindcss/cli 4.2.2`
- `daisyui 5.5.19`
- release channel `v4.2.2-rc1`
- storage prefix `tailwind_cli_daisyui`
- public storage base URL `https://storage.defdo.de`

This plan focuses first on repeatable remote releases. The full `tailwind_builder_hub` and installable worker model should build on top of this release path, not replace it.

## Current State

Completed foundations:

- Canonical target normalization exists in `Defdo.TailwindBuilder.Core.Targets`.
- DaisyUI v5 defaults are pinned to `5.5.19`.
- Tailwind `4.2.2` source checksum is configured across providers.
- `Defdo.TailwindBuilder.Release` orchestrates download, plugin patching, build, smoke test, manifest generation, checksum generation, and deploy.
- `mix tailwind.release` exists for the `v4.2.2-rc1` release flow.
- R2-style environment names are supported by the release task.
- Release flow, deployer metadata, and target normalization have test coverage.
- Thin `tailwind_builder_hub` and `tailwind_builder_worker` scaffolds now exist as sibling projects.

Open risks:

- Resolved: R2 storage config now uses the explicit `:storage` app-env key (not `:aws`).
- Resolved: R2 host normalization accepts both raw hosts and `https://...` input (`Deployer.normalize_storage_host/1`).
- Resolved: the manifest now carries `manifest_schema_version` and separates `tailwind_version`, `tailwind_cli_version`, and `release_channel`, plus per-artifact fields (`target_key`, `build_target`, `artifact_name`, `storage_url`, `checksum_sha256`, `size_bytes`, `built_at`) and a locally observable `provenance` map.
- Resolved: release idempotency is explicit via `:overwrite_policy` (`:fail`, `:overwrite`, `:promote_only`) resolved by `Deployer.resolve_overwrite_plan/4`; reruns are deterministic against the policy. Cross-channel promotion (Phase 3) is still open.
- Resolved: `--dry-run` runs all local steps and produces manifest/checksums without uploading.
- Resolved: post-upload verification (`Deployer.verify_uploaded_artifacts/2`, gated by `:verify_upload`, wired through `Release.run/1` and `mix tailwind.release --verify-upload`) now also smoke tests the downloaded artifact when `:verify_smoke_test` / `--verify-smoke-test` is set, downgrading to `:smoke_failed` and aborting metadata publish on failure.
- Resolved: storage uploads now use a generous, configurable receive timeout (`Deployer.resolve_upload_timeout/1`, default `300_000` ms, override via `:tailwind_builder, :storage` `:upload_timeout`). Large standalone binaries (>70 MB) over a slow link previously surfaced `%Req.TransportError{reason: :timeout}` on the response read even though the object uploaded.
- Proven: first real `v4.2.2-rc1` publish to R2 / `https://storage.defdo.de` for `macos-arm64`. Real dry-run, real upload, public download, downloaded-artifact smoke test, and external (curl/jq/sha256) consumer validation all succeeded; `manifest.json` + `sha256sums.txt` published and agree with artifact bytes (sha256 `6c426808…`). Single host target; other targets unpublished.
- Proven: deployer `--verify-upload` + `--verify-smoke-test` pipeline against real R2, via a canary release (`tailwind_cli_daisyui_canary/v4.2.2-rc1-verify-canary`). Full path: real upload → deployer HEAD existence check → deployer public fetch → checksum verify (expected==actual `820b187d…`) → smoke `:passed` → metadata published only after verification. Production prefix untouched.
- Remote execution is still manual per host.

## MVP Cutline

The MVP is usable when one supported host can produce a verified `v4.2.2-rc1` artifact, publish it to R2, publish metadata, and provide enough manifest data for `tailwind_compiler` to consume it without hard-coded binary URLs.

The MVP does not include:

- full Phoenix Hub scheduling UI
- installable worker services
- distributed auth
- automatic multi-host scheduling
- stable-channel promotion

Those pieces are follow-up platform work. Do not delay the MVP for them.

## Continuity Rules for Implementation Agents

These rules are intended for Kimi, DeepSeek, Codex, and any other implementation agent continuing this work.

- Keep all repository content in English.
- Work from `RELEASE_WORK_PLAN.md` before introducing new architecture.
- Prefer small, reviewable changes with tests over broad rewrites.
- Do not start `tailwind_builder_hub` until the release artifact contract works end to end.
- Do not add a new HTTP client. Use `Req` and `ReqS3`.
- Do not rename public APIs unless the change is required for the MVP and tests are updated in the same patch.
- Do not remove compatibility for existing release task options unless a replacement is documented.
- Do not publish metadata before artifact verification succeeds.
- Do not guess target mappings. Use `Defdo.TailwindBuilder.Core.Targets`.
- Do not use `latest` for Tailwind, DaisyUI, or CLI versions in release code.
- Treat missing target support as a reportable state, not as a failed release.
- Every behavior change must include focused tests or an explicit note explaining why it cannot be tested locally.

## Daily Execution Path

Use this sequence over the next few implementation days:

1. Make the local release command deterministic and R2-safe.
2. Produce a dry-run manifest and checksum set.
3. Publish one real target to `v4.2.2-rc1`.
4. Verify the published artifact through public storage URL download, checksum validation, and smoke test.
5. Hand the manifest contract to `tailwind_compiler`.
6. Only then add remote SSH execution.

## Definition of Done for Each Task

A task is complete only when:

- the intended command or public function is documented;
- tests cover the normal path and at least one failure path;
- generated manifest data is compatible with `tailwind_compiler` needs;
- errors include actionable metadata;
- `mix test` or the relevant targeted test command has been run;
- the next task can start without hidden local state.

## Phase 1: Release Reliability

Objective: make one local or remote host able to produce and publish a verifiable artifact without manual post-checks.

Tasks:

- Rename runtime storage config from internal `:aws` semantics to an explicit storage/R2 config while keeping `ReqS3` signing under the hood.
- Normalize `R2_HOST` so both `<account>.r2.cloudflarestorage.com` and `https://<account>.r2.cloudflarestorage.com` work.
- Add a release manifest schema version.
- Add separate manifest fields for `tailwind_version`, `tailwind_cli_version`, and `release_channel`.
- Add per-artifact fields for `target_key`, `build_target`, `artifact_name`, `storage_url`, `checksum_sha256`, `size_bytes`, and `built_at`.
- Add build provenance fields: builder hostname, OS, arch, Elixir version, Node version, Rust version, Bun or pnpm version, source checksum, and git SHA when available.
- Add an explicit overwrite policy: `:fail`, `:overwrite`, or `:promote_only`.
- Add `dry_run: true` support that runs all local steps and produces manifest/checksum output without uploading to R2.
- After upload, fetch each artifact from `storage_base_url`, validate sha256, and run a smoke test against the downloaded artifact.
- Publish `manifest.json` and `sha256sums.txt` only after artifact verification succeeds.

Acceptance criteria:

- `mix tailwind.release --channel v4.2.2-rc1 --plugin daisyui_v5 --smoke-test` fails before publishing metadata if any artifact is invalid.
- The same release command can be run twice and returns a deterministic result based on the selected overwrite policy.
- `manifest.json` is sufficient for `tailwind_compiler` to download and validate the correct binary without hard-coded version defaults.
- Test coverage includes R2 host normalization, dry run, manifest shape, overwrite behavior, and post-upload verification.

## Phase 2: Remote Release MVP

Objective: remove the need to manually run the release command machine by machine.

Tasks:

- Done: `Defdo.TailwindBuilder.HostCapability` — local/remote probe via injectable runner,
  returns `target_key`, `build_target`, `artifact_name` from `Core.Targets`, OS, arch,
  all required tool versions; missing tools reported as `nil` fields, not crashes.
- Done: `Defdo.TailwindBuilder.Remote.SSHExecutor` — thin `System.cmd("ssh",...)` wrapper
  with injectable `:runner` for test doubles, `redact_secrets/2` for safe logging,
  `build_ssh_flags/2` for inspection.
- Done: `Defdo.TailwindBuilder.Remote.Release` — orchestrates: capability probe → command
  build → SSH execution → manifest fetch for artifact metadata → structured JSON report write.
- Done: `Defdo.TailwindBuilder.Remote.MissingTargets` — pure target-gap helper comparing
  desired/published/buildable/failed; `published_from_manifest/1` extracts from manifest map.
- Done: `mix tailwind.release.remote` Mix task with full CLI option set.
- Done: Test coverage: capability, ssh_executor, missing_targets, remote release, Mix task.
  All tests use injectable runners; no real SSH host required.

Acceptance criteria:

- One command can build and publish from a configured remote host. ✓ (SSH execution wired end-to-end; manual SSH smoke pending — no remote Linux builder available at commit time)
- A failed remote build returns structured failure metadata and preserves logs. ✓
- A target that is unavailable is reported as `missing`, not as a release blocker. ✓
- The release report can be used later by `tailwind_builder_hub` without changing its shape. ✓ (`schema_version: 1`, all documented keys stable)

Open:

- Manual SSH smoke against a real remote Linux host (pending hardware access).
- Full multi-host orchestration (Phase 4 / Hub scheduler).

## Phase 3: Release Promotion

Objective: promote verified release candidates into stable channels without rebuilding.

Tasks:

- Define promotion from `v4.2.2-rc1` to `v4.2.2`.
- Verify source channel artifacts before promotion.
- Copy artifacts and metadata to the stable channel.
- Regenerate stable-channel manifest URLs.
- Preserve immutable checksums.
- Add rollback by repointing or republishing stable metadata to a previous verified channel.

Acceptance criteria:

- Promotion never rebuilds binaries.
- Promotion fails if any source artifact checksum does not match the release candidate manifest.
- Stable manifest entries point to stable storage URLs and keep the same artifact checksums.

## Phase 4: Hub and Worker Foundation

Objective: evolve the release flow into `tailwind_builder_hub` and `tailwind_builder_worker`.

Tasks:

- Keep `tailwind_builder` as the shared core.
- Create `tailwind_builder_hub` for workers, jobs, releases, artifacts, auth, dashboard, and API.
- Create `tailwind_builder_worker` as an installable OTP release with embedded ERTS.
- Use HTTP polling for the first worker protocol.
- Use LiveView only for the dashboard.
- Use PubSub for internal Hub updates.
- Reuse the release report and manifest schema from earlier phases.
- Keep the current scaffolds thin until the artifact contract is stable.

Acceptance criteria:

- A worker can register, heartbeat, advertise capabilities, pull a job, run the release flow, and report results.
- The Hub can derive `published`, `buildable_now`, `missing`, `failed`, `stale`, and `building` states.
- Auth can be added through the existing Defdo token flow without changing the artifact contract.

## Immediate Next Tasks

1. Done: R2 storage config naming and host normalization.
2. Done: manifest schema with separate Tailwind CLI and provenance fields.
3. Done: `dry_run` and post-upload artifact verification.
4. Done: first real `v4.2.2-rc1` publish from one host (`macos-arm64`), externally verified.
5. Available, not yet consumed: a documented manifest contract + sample for
   `tailwind_compiler` (`docs/MANIFEST_CONSUMER_CONTRACT.md`,
   `docs/sample_manifest.v4.2.2-rc1.json`). Updating `tailwind_compiler` itself
   to consume `manifest.json` is the next open task.
6. Next: publish the remaining host targets, then add remote SSH execution.

## MVP Command Targets

The MVP should preserve these commands:

```bash
mix test
```

```bash
mix tailwind.release \
  --version 4.2.2 \
  --channel v4.2.2-rc1 \
  --config-provider testing \
  --bucket defdo \
  --prefix tailwind_cli_daisyui \
  --storage-base-url https://storage.defdo.de \
  --plugin daisyui_v5 \
  --smoke-test
```

The release command should also support a dry-run mode before the first real upload:

```bash
mix tailwind.release \
  --version 4.2.2 \
  --channel v4.2.2-rc1 \
  --config-provider testing \
  --bucket defdo \
  --prefix tailwind_cli_daisyui \
  --storage-base-url https://storage.defdo.de \
  --plugin daisyui_v5 \
  --smoke-test \
  --dry-run
```

`--dry-run` is not implemented yet. It is part of Phase 1.
