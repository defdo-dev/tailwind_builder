defmodule Mix.Tasks.Tailwind.Release.Remote do
  @moduledoc """
  Build and publish a Tailwind standalone binary on a single remote host over SSH.

  Runs the existing `mix tailwind.release` flow on the configured host by:

  1. Detecting remote host capabilities via SSH.
  2. Aborting (with a structured report) if the host lacks required tools.
  3. Running `mix tailwind.release` on the remote with injected R2 credentials.
  4. Capturing stdout, exit status, and artifact metadata.
  5. Writing a local JSON report to `--report-path`.

  ## Usage

      mix tailwind.release.remote \\
        --host builder.example.com \\
        --workdir /home/build/tailwind_builder \\
        --version 4.2.2 \\
        --channel v4.2.2-rc1 \\
        --config-provider testing \\
        --bucket defdo \\
        --prefix tailwind_cli_daisyui \\
        --storage-base-url https://storage.defdo.de \\
        --plugin daisyui_v5 \\
        --smoke-test \\
        --verify-upload \\
        --verify-smoke-test \\
        --overwrite-policy fail \\
        --report-path ./tmp/tailwind-release-report.json

  ## R2 Credentials

  The remote host needs R2 credentials to publish artifacts. Provide them via
  environment variables on the **local** machine:

      R2_ACCESS_KEY_ID=...  R2_SECRET_ACCESS_KEY=...  R2_HOST=...  mix tailwind.release.remote ...

  Credentials are passed as shell environment variable assignments in the SSH
  command and are **never logged** (they appear as `[REDACTED]` in all output).

  ## Report

  The JSON report written to `--report-path` has `schema_version: 1` and can
  be consumed by `tailwind_builder_hub` without format changes. The report is
  written even on remote build failure so that logs and exit status are preserved.

  ## SSH options

    * `--ssh-identity path` — path to SSH private key (equivalent to `ssh -i`).
  """

  use Mix.Task

  alias Defdo.TailwindBuilder.Remote.Release, as: RemoteRelease

  @shortdoc "Build and publish a Tailwind release on a remote SSH host"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          host: :string,
          workdir: :string,
          version: :string,
          channel: :string,
          config_provider: :string,
          bucket: :string,
          prefix: :string,
          storage_base_url: :string,
          plugin: :string,
          smoke_test: :boolean,
          verify_upload: :boolean,
          verify_smoke_test: :boolean,
          overwrite_policy: :string,
          report_path: :string,
          ssh_identity: :string
        ]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    host = Keyword.get(opts, :host) || Mix.raise("--host is required")
    workdir = Keyword.get(opts, :workdir) || Mix.raise("--workdir is required")

    release_opts = [
      host: host,
      workdir: workdir,
      version: Keyword.get(opts, :version, "4.2.2"),
      release_channel: Keyword.get(opts, :channel, "v4.2.2-rc1"),
      plugin: Keyword.get(opts, :plugin, "daisyui_v5"),
      bucket: Keyword.get(opts, :bucket, System.get_env("TAILWIND_R2_BUCKET", "defdo")),
      prefix:
        Keyword.get(opts, :prefix, System.get_env("TAILWIND_R2_PREFIX", "tailwind_cli_daisyui")),
      storage_base_url:
        Keyword.get(
          opts,
          :storage_base_url,
          System.get_env("TAILWIND_STORAGE_BASE_URL", "https://storage.defdo.de")
        ),
      config_provider: Keyword.get(opts, :config_provider, "testing"),
      overwrite_policy: Keyword.get(opts, :overwrite_policy, "fail"),
      smoke_test: Keyword.get(opts, :smoke_test, false),
      verify_upload: Keyword.get(opts, :verify_upload, false),
      verify_smoke_test: Keyword.get(opts, :verify_smoke_test, false),
      report_path: Keyword.get(opts, :report_path, "./tmp/tailwind-release-report.json"),
      ssh_identity: Keyword.get(opts, :ssh_identity)
    ]

    Mix.shell().info("Remote release: #{host}")
    Mix.shell().info("  Target workdir: #{workdir}")

    case RemoteRelease.run(release_opts) do
      {:ok, report} ->
        status = report["status"]
        report_path = release_opts[:report_path]

        case status do
          "published" ->
            Mix.shell().info("Remote release succeeded: #{status}")
            Mix.shell().info("  Target: #{get_in(report, ["capability", "target_key"])}")
            Mix.shell().info("  Report: #{report_path}")

          "not_buildable" ->
            missing = get_in(report, ["capability", "missing_tools"]) || []
            Mix.shell().info("Remote host not build-capable.")
            Mix.shell().info("  Missing tools: #{Enum.join(missing, ", ")}")
            Mix.shell().info("  Report: #{report_path}")

          "failed" ->
            exit_status = get_in(report, ["logs", "exit_status"])
            stdout_path = get_in(report, ["logs", "stdout_path"])
            Mix.shell().error("Remote release failed (exit #{exit_status})")
            Mix.shell().info("  Stdout log: #{stdout_path}")
            Mix.shell().info("  Report: #{report_path}")
            Mix.raise("Remote release failed with exit status #{exit_status}")

          other ->
            Mix.shell().info("Remote release status: #{other}")
            Mix.shell().info("  Report: #{report_path}")
        end

      {:error, reason} ->
        Mix.raise("Remote release error: #{inspect(reason)}")
    end
  end
end
