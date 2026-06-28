defmodule Defdo.TailwindBuilder.Remote.Release do
  @moduledoc """
  Orchestrates a Tailwind standalone binary release on a single remote host
  over SSH.

  This module owns the remote release flow:

  1. Detect the remote host's canonical `target_key` via SSH capability probe.
  2. If the host is not build-capable, return a `:not_buildable` report.
  3. Build the `mix tailwind.release` shell command for that single target.
  4. Execute the command on the remote host via SSH, capturing stdout and exit status.
  5. On success, optionally fetch the published `manifest.json` to obtain
     artifact metadata for the report.
  6. Write a structured JSON report to a local file.

  ## Options

  - `:host` — SSH host (required).
  - `:workdir` — path on the remote host where `tailwind_builder` is checked out (required).
  - `:version` — Tailwind CLI version, e.g. `"4.2.2"`.
  - `:release_channel` — release channel, e.g. `"v4.2.2-rc1"`.
  - `:plugin` — plugin key, e.g. `"daisyui_v5"`.
  - `:bucket` — storage bucket name.
  - `:prefix` — storage prefix, e.g. `"tailwind_cli_daisyui"`.
  - `:storage_base_url` — public base URL, e.g. `"https://storage.defdo.de"`.
  - `:config_provider` — config provider name (e.g. `"testing"`).
  - `:overwrite_policy` — one of `"fail"`, `"overwrite"`, `"promote_only"`.
  - `:smoke_test` — boolean.
  - `:verify_upload` — boolean.
  - `:verify_smoke_test` — boolean.
  - `:report_path` — local filesystem path to write the JSON report (default: `./tmp/tailwind-release-report.json`).
  - `:ssh_identity` — path to SSH private key.
  - `:ssh_options` — extra SSH flags list.
  - `:ssh_runner` — injectable SSH command runner for tests. Must match `(host, command, opts -> {:ok, map} | {:error, term})`.
  - `:cap_runner` — injectable runner for the capability probe (overrides SSH for the probe step).
  - `:r2_access_key_id` — R2 credential passed to the remote env.
  - `:r2_secret_access_key` — R2 credential passed to the remote env.
  - `:r2_host` — R2 endpoint host.
  - `:r2_region` — R2 region (default `"auto"`).

  ## Report

  The local JSON report has `schema_version: 1` and can be consumed by
  `tailwind_builder_hub` without format changes.
  """

  require Logger

  alias Defdo.TailwindBuilder.HostCapability
  alias Defdo.TailwindBuilder.Remote.{MissingTargets, SSHExecutor}

  @default_version "4.2.2"
  @default_channel "v4.2.2-rc1"
  @default_plugin "daisyui_v5"
  @default_storage_base_url "https://storage.defdo.de"
  @default_prefix "tailwind_cli_daisyui"
  @default_bucket "defdo"
  @default_report_path "./tmp/tailwind-release-report.json"

  @doc """
  Run a remote release and write a local JSON report.

  Returns `{:ok, report_map}` on success or `{:error, reason}` when the
  execution cannot start (e.g. capability probe fails due to SSH error).
  A non-zero exit from the remote `mix tailwind.release` is not an Elixir
  error — it is captured in the report with `status: "failed"`.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) do
    host = Keyword.fetch!(opts, :host)
    workdir = Keyword.fetch!(opts, :workdir)
    version = Keyword.get(opts, :version, @default_version)
    release_channel = Keyword.get(opts, :release_channel, @default_channel)
    plugin = Keyword.get(opts, :plugin, @default_plugin)
    bucket = Keyword.get(opts, :bucket, @default_bucket)
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    storage_base_url = Keyword.get(opts, :storage_base_url, @default_storage_base_url)
    config_provider = Keyword.get(opts, :config_provider, "testing")
    overwrite_policy = Keyword.get(opts, :overwrite_policy, "fail")
    smoke_test = Keyword.get(opts, :smoke_test, false)
    verify_upload = Keyword.get(opts, :verify_upload, false)
    verify_smoke_test = Keyword.get(opts, :verify_smoke_test, false)
    report_path = Keyword.get(opts, :report_path, @default_report_path)
    ssh_runner = Keyword.get(opts, :ssh_runner)
    cap_runner = Keyword.get(opts, :cap_runner)

    r2_creds = build_r2_creds(opts)

    Logger.info("Remote release: probing capabilities on #{host}")

    cap_result =
      if cap_runner do
        HostCapability.detect(runner: cap_runner)
      else
        HostCapability.detect_remote(host, ssh_runner_to_opt(ssh_runner, opts))
      end

    case cap_result do
      {:error, reason} ->
        {:error, {:capability_probe_failed, host, reason}}

      capability when is_map(capability) ->
        execute_with_capability(capability, host, workdir, %{
          version: version,
          release_channel: release_channel,
          plugin: plugin,
          bucket: bucket,
          prefix: prefix,
          storage_base_url: storage_base_url,
          config_provider: config_provider,
          overwrite_policy: overwrite_policy,
          smoke_test: smoke_test,
          verify_upload: verify_upload,
          verify_smoke_test: verify_smoke_test,
          report_path: report_path,
          ssh_runner: ssh_runner,
          r2_creds: r2_creds,
          raw_opts: opts
        })
    end
  end

  @doc """
  Build the shell command string that would be run on the remote host.

  Returns `{actual_command, redacted_command}`. Log only the redacted form.
  """
  @spec build_release_command(String.t(), String.t(), map()) ::
          {String.t(), String.t()}
  def build_release_command(workdir, _target_key, params) do
    r2 = params.r2_creds || %{}

    env_prefix =
      [
        r2_env("R2_ACCESS_KEY_ID", r2[:access_key_id]),
        r2_env("R2_SECRET_ACCESS_KEY", r2[:secret_access_key]),
        r2_env("R2_HOST", r2[:host]),
        r2_env("R2_REGION", r2[:region] || "auto")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    mix_args =
      [
        "mix tailwind.release",
        "--version #{params.version}",
        "--channel #{params.release_channel}",
        "--plugin #{params.plugin}",
        "--bucket #{params.bucket}",
        "--prefix #{params.prefix}",
        "--storage-base-url #{params.storage_base_url}",
        "--config-provider #{params.config_provider}",
        "--overwrite-policy #{params.overwrite_policy}",
        if(params.smoke_test, do: "--smoke-test", else: nil),
        if(params.verify_upload, do: "--verify-upload", else: nil),
        if(params.verify_smoke_test, do: "--verify-smoke-test", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" \\\n  ")

    actual = "cd #{workdir} && #{env_prefix} #{mix_args}"

    secret_map =
      [r2[:access_key_id], r2[:secret_access_key]]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(byte_size(&1) == 0))
      |> Enum.map(&{&1, "[REDACTED]"})
      |> Enum.into(%{})

    redacted = SSHExecutor.redact_secrets(actual, secret_map)
    {actual, redacted}
  end

  defp execute_with_capability(capability, host, workdir, params) do
    if capability.build_capable do
      run_release_on_host(capability, host, workdir, params)
    else
      report =
        build_report(params, host, workdir, capability, %{
          status: "not_buildable",
          artifact: nil,
          logs: %{"stdout_path" => nil, "stderr_path" => nil, "exit_status" => nil},
          verification: skipped_verification()
        })

      write_report(report, params.report_path)
      {:ok, report}
    end
  end

  defp run_release_on_host(capability, host, workdir, params) do
    {actual_cmd, redacted_cmd} =
      build_release_command(workdir, capability.target_key, params)

    Logger.info("Remote release: running on #{host} for target #{capability.target_key}")
    Logger.info("SSH command (redacted): #{redacted_cmd}")

    ssh_opts = build_ssh_opts(params)

    result =
      if params.ssh_runner do
        params.ssh_runner.(host, actual_cmd, ssh_opts)
      else
        SSHExecutor.run(host, actual_cmd, ssh_opts)
      end

    case result do
      {:error, reason} ->
        {:error, {:ssh_failed, host, reason}}

      {:ok, ssh_result} ->
        process_ssh_result(ssh_result, capability, host, workdir, params)
    end
  end

  defp process_ssh_result(ssh_result, capability, host, workdir, params) do
    stdout_path = write_stdout_log(ssh_result.stdout, params.report_path)

    {status, artifact} =
      if ssh_result.exit_status == 0 do
        artifact = fetch_artifact_from_manifest(params, capability.target_key)
        {"published", artifact}
      else
        {"failed", nil}
      end

    verification =
      if params.verify_upload and status == "published" do
        %{
          "upload_verified" => true,
          "smoke_tested_download" => params.verify_smoke_test,
          "status" => "passed"
        }
      else
        skipped_verification()
      end

    report =
      build_report(params, host, workdir, capability, %{
        status: status,
        artifact: artifact,
        logs: %{
          "stdout_path" => stdout_path,
          "stderr_path" => nil,
          "exit_status" => ssh_result.exit_status
        },
        verification: verification
      })

    write_report(report, params.report_path)
    {:ok, report}
  end

  defp build_report(params, host, workdir, capability, extra) do
    missing_targets =
      MissingTargets.report(
        desired: [capability.target_key],
        published: if(extra.status == "published", do: [capability.target_key], else: []),
        buildable: if(capability.build_capable, do: [capability.target_key], else: []),
        failed: if(extra.status == "failed", do: [capability.target_key], else: [])
      )

    %{
      "schema_version" => 1,
      "executed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "release_channel" => params.release_channel,
      "tailwind_version" => params.version,
      "tailwind_cli_version" => params.version,
      "plugin" => params.plugin,
      "remote" => %{
        "host" => host,
        "workdir" => workdir,
        "hostname" => capability.hostname,
        "os" => capability.os,
        "arch" => capability.arch
      },
      "capability" => %{
        "target_key" => capability.target_key,
        "build_target" => capability.build_target,
        "artifact_name" => capability.artifact_name,
        "build_capable" => capability.build_capable,
        "missing_tools" => capability.missing_tools,
        "elixir_version" => capability.elixir_version,
        "otp_release" => capability.otp_release,
        "node_version" => capability.node_version,
        "rust_version" => capability.rust_version,
        "bun_version" => capability.bun_version,
        "pnpm_version" => capability.pnpm_version,
        "git_sha" => capability.git_sha
      },
      "status" => extra.status,
      "artifact" => serialize_artifact(extra.artifact),
      "verification" => stringify_keys(extra.verification),
      "logs" => stringify_keys(extra.logs),
      "missing_targets" => stringify_keys(missing_targets)
    }
  end

  defp fetch_artifact_from_manifest(params, target_key) do
    manifest_url =
      "#{params.storage_base_url}/#{params.prefix}/#{params.release_channel}/manifest.json"

    case fetch_json(manifest_url) do
      {:ok, manifest} ->
        files = Map.get(manifest, "files", [])

        Enum.find(files, fn f ->
          Map.get(f, "target_key") == target_key
        end)

      {:error, reason} ->
        Logger.warning("Could not fetch manifest after release: #{inspect(reason)}")
        nil
    end
  end

  defp fetch_json(url) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    url_charlist = String.to_charlist(url)

    http_opts = [
      ssl: [
        verify: :verify_peer,
        cacertfile: CAStore.file_path() |> String.to_charlist(),
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ],
      timeout: 30_000
    ]

    case :httpc.request(:get, {url_charlist, []}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(body) do
          {:ok, map} -> {:ok, map}
          {:error, reason} -> {:error, {:json_decode, inspect(reason)}}
        end

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_request_failed, reason}}
    end
  end

  defp write_report(report, path) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    json = Jason.encode!(report, pretty: true)
    File.write!(path, json)
    Logger.info("Remote release report written: #{path}")
    :ok
  end

  defp write_stdout_log(stdout, report_path) do
    dir = Path.dirname(report_path)
    base = Path.basename(report_path, ".json")
    log_path = Path.join(dir, "#{base}-stdout.log")
    File.mkdir_p!(dir)
    File.write!(log_path, stdout)
    log_path
  end

  defp serialize_artifact(nil), do: nil

  defp serialize_artifact(artifact) when is_map(artifact) do
    %{
      "target_key" => Map.get(artifact, "target_key") || Map.get(artifact, :target_key),
      "build_target" => Map.get(artifact, "build_target") || Map.get(artifact, :build_target),
      "artifact_name" => Map.get(artifact, "artifact_name") || Map.get(artifact, :artifact_name),
      "storage_url" => Map.get(artifact, "storage_url") || Map.get(artifact, :storage_url),
      "checksum_sha256" =>
        Map.get(artifact, "checksum_sha256") || Map.get(artifact, :checksum_sha256),
      "size_bytes" => Map.get(artifact, "size_bytes") || Map.get(artifact, :size_bytes),
      "built_at" => Map.get(artifact, "built_at") || Map.get(artifact, :built_at)
    }
  end

  defp skipped_verification do
    %{"upload_verified" => false, "smoke_tested_download" => false, "status" => "skipped"}
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {k, stringify_value(v)}
    end)
  end

  defp stringify_keys(other), do: other

  defp stringify_value(v) when is_map(v), do: stringify_keys(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v), do: v

  defp build_r2_creds(opts) do
    %{
      access_key_id: Keyword.get(opts, :r2_access_key_id, System.get_env("R2_ACCESS_KEY_ID")),
      secret_access_key:
        Keyword.get(opts, :r2_secret_access_key, System.get_env("R2_SECRET_ACCESS_KEY")),
      host: Keyword.get(opts, :r2_host, System.get_env("R2_HOST")),
      region: Keyword.get(opts, :r2_region, System.get_env("R2_REGION", "auto"))
    }
  end

  defp r2_env(_key, nil), do: nil
  defp r2_env(_key, ""), do: nil
  defp r2_env(key, value), do: "#{key}=#{shell_quote(value)}"

  defp shell_quote(value), do: "'#{String.replace(value, "'", "'\\''")}'"

  defp build_ssh_opts(params) do
    raw = params.raw_opts || []
    [identity: Keyword.get(raw, :ssh_identity)] |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end

  defp ssh_runner_to_opt(nil, opts) do
    Keyword.take(opts, [:ssh_identity, :ssh_options, :timeout])
  end

  defp ssh_runner_to_opt(runner, opts) do
    Keyword.take(opts, [:ssh_identity, :ssh_options, :timeout]) ++ [runner: runner]
  end
end
