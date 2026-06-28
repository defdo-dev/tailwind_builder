# AGENTS.md

This file provides guidance to Codex and other contributors when working in `tailwind_builder`.

It consolidates the conventions repeatedly used across `defdo_projects` and adapts them to the current goal of this repository: improve the shared build core and ship Tailwind CSS `4.2.2` remotely as soon as possible.

## Common Commands

### Development

- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `mix test` - Run the full test suite
- `mix test test/path/to/file.exs` - Run a specific test file
- `mix format` - Format code according to `.formatter.exs`
- `mix tailwind.setup` - Install local Tailwind build dependencies

### Debugging

- `mix test --failed` - Re-run only the previously failed tests
- `mix help <task>` - Read task docs before introducing a new task into the workflow

## Architecture Snapshot

This repository is the shared build core, not the final hub application.

Primary modules:

- `Defdo.TailwindBuilder.Core`
  Technical constraints, architecture support, and planning primitives
- `Defdo.TailwindBuilder.Downloader`
  Source download and extraction
- `Defdo.TailwindBuilder.PluginManager`
  Plugin integration
- `Defdo.TailwindBuilder.Builder`
  Compilation
- `Defdo.TailwindBuilder.Deployer`
  Artifact publication
- `Defdo.TailwindBuilder.Orchestrator`
  End-to-end pipeline composition
- `Defdo.TailwindBuilder.NodeManager`
  Early worker registration and heartbeat draft
- `Defdo.TailwindBuilder.RemoteBuilder`
  Client for a future remote build hub
- `Defdo.TailwindBuilder.GitHubBuilder`
  GitHub Actions backend integration
- `Defdo.TailwindBuilder.SmartBuilder`
  Strategy selection across local and remote execution

The current hub direction is documented in `HUB_ARCHITECTURE.md`.

## Consolidated Project Rules

### Language and Documentation

- Keep repository-facing code comments, docs, changelog entries, and architectural notes in English.
- Conversation with the user may be in Spanish, but committed repository content must stay in English.

### HTTP and External Calls

- Use the already included `Req` client for HTTP calls.
- Do not introduce `:httpoison`, `:tesla`, or `:httpc` wrappers unless explicitly required.

### Elixir Rules

- Never use map access syntax on structs. Use dot access or the appropriate API.
- Never use `String.to_atom/1` on user input or unconstrained external values.
- Keep predicate functions in the `foo?/1` style rather than `is_foo/1`, except for guards.
- Never nest multiple modules in one file.
- When rebinding values across `if`, `case`, or `cond`, bind the full expression result.
- Do not use `Mix.env()` in runtime code. If runtime environment branching becomes necessary, read it from application config.

### Failure Semantics

- Prefer explicit failure over silent fallback when target metadata, release metadata, or worker capabilities are missing.
- Do not hide missing target mappings behind guessed defaults.
- If a struct needs required fields, demand them explicitly instead of inventing fallback values.

### Concurrency and OTP

- Prefer OTP primitives already in use (`GenServer`, `DynamicSupervisor`, `Registry`, `Task.async_stream`) over ad hoc process orchestration.
- Use `Task.async_stream/3` for concurrent multi-target work with back-pressure when appropriate.
- Keep worker lifecycle and build lifecycle separate; a worker process is not the same thing as a build job.

### Testing

- Use `start_supervised!/1` to start processes in tests.
- Avoid `Process.sleep/1` for synchronization.
- Prefer `Process.monitor/1`, mailbox assertions, and `:sys.get_state/1` when synchronizing tests.
- Add or update tests alongside core behavior changes, especially around target normalization and release metadata.

## Immediate Product Goals

The near-term goal is not the full platform. The near-term goal is to make the core capable of shipping the next release safely.

### Current Release Target

- `tailwindcss 4.2.2`
- `@tailwindcss/cli 4.2.2`
- `daisyui 5.5.19`
- Publish first as `v4.2.2-rc1`

### Core Priorities

1. Normalize target naming across the repository.
   The codebase currently mixes product-facing targets such as `linux-x64` and `darwin-arm64` with toolchain targets such as `aarch64-apple-darwin`.
2. Introduce a canonical target model.
   The shared core should expose `target_key`, `build_target`, and `artifact_name` translation helpers.
3. Make the release contract explicit.
   Every published release should produce artifacts, `manifest.json`, and `sha256sums.txt`.
4. Make smoke tests first-class.
   Every released binary must successfully compile:

   ```css
   @import "tailwindcss";
   @plugin "daisyui";
   ```

5. Improve the core before building the full UI.
   Prefer landing shared-library improvements before expanding the thin Phoenix hub or installable worker scaffolds as sibling projects.

## Delivery Boundaries

### What belongs here

- Shared target normalization
- Build orchestration logic
- Plugin version alignment
- Release metadata generation
- Smoke testing helpers
- Remote execution backends that the future hub can reuse

### What does not belong here yet

- Full Hub scheduling and persistence
- Full worker installer and service management
- Auth-specific implementation details that belong to hub or worker apps

## Remote Build Strategy

Until the full hub and installable worker exist, these execution backends are acceptable:

- SSH to controlled build hosts
- GitHub Actions for temporary or hosted capacity
- A future native worker protocol

Do not block core work on the existence of the final hub.

## Architecture Intent

- `tailwind_builder` remains the reusable shared core.
- `tailwind_builder_hub` will become the orchestration and visibility layer.
- `tailwind_builder_worker` will eventually become the installable execution agent.

LiveView is for the hub UI only. It is not the worker transport.

## Current Refactor Direction

When making architecture changes, prefer this sequence:

1. Fix and simplify the shared core API.
2. Normalize target semantics.
3. Align plugin and release defaults to the intended shipped versions.
4. Add coverage for the new release path.
5. Only then expand into hub or worker applications.

## Existing Mismatch to Keep in Mind

- Several modules still default to Tailwind `4.1.x` even though the next delivery target is `4.2.2`.
- Remote and deployment paths still use inconsistent target strings.
- The current library already sketches hub concepts, but it is not yet a Phoenix hub or a durable worker system.
- Do not flip the global Tailwind default to `4.2.2` until the full build and publish path is validated.

Any change that moves the repository toward a reliable `4.2.2` release path should be preferred over speculative platform work.

## MVP Continuity

Use `RELEASE_WORK_PLAN.md` as the source of truth for the next implementation passes.

Implementation agents must preserve these priorities:

1. Make the release flow deterministic on one host.
2. Make R2 uploads and public verification reliable.
3. Make the manifest detailed enough for `tailwind_compiler`.
4. Add remote SSH execution only after the local release flow is verified.
5. Defer Hub and Worker applications until the artifact contract is stable.

The current repository now contains thin hub and worker scaffolds, but they
must remain layout- and runtime-boundary level until the artifact contract is
stable.

When continuing from another model's work, first inspect:

- `git status --short`
- `RELEASE_WORK_PLAN.md`
- `HUB_ARCHITECTURE.md`
- recent tests around `Release`, `Deployer`, and `Core.Targets`

Do not assume previous context is correct if the code contradicts it.
