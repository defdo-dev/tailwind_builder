defmodule Defdo.TailwindBuilder.Deployer do
  @moduledoc """
  Specialized module for distributing compiled binaries with comprehensive telemetry.

  Responsibilities:
  - Upload binaries to different destinations (S3, R2, etc.) with performance tracking
  - Validate binaries before distribution
  - Handle version metadata
  - Generate distribution manifests
  - Monitor deployment performance and success rates

  Does not handle compilation or download, only final distribution.
  """

  require Logger
  alias Defdo.TailwindBuilder.{Core, PluginProbes, Telemetry}
  alias Defdo.TailwindBuilder.Core.Targets

  @doc """
  Deploy compiled binaries to a destination with comprehensive telemetry tracking
  """
  def deploy(opts \\ []) do
    # Use telemetry wrapper for comprehensive tracking
    target = determine_target_from_opts(opts)

    Telemetry.track_deploy(target, fn ->
      do_deploy(opts)
    end)
  end

  # Helper function to determine deployment target from options
  defp determine_target_from_opts(opts) do
    cond do
      # S3 or R2 based on bucket
      opts[:bucket] -> :cloud
      opts[:destination] && String.starts_with?(opts[:destination], "/") -> :local
      true -> :unknown
    end
  end

  defp do_deploy(opts) do
    opts =
      Keyword.validate!(opts, [
        :version,
        :source_path,
        :destination,
        :bucket,
        :prefix,
        :validate_binaries,
        :generate_manifest,
        :generate_checksums,
        :release_channel,
        :plugin_set,
        :storage_base_url,
        :smoke_test_binaries,
        :smoke_test_opts,
        :verify_upload,
        :verification_fetcher,
        :verification_timeout,
        :verify_smoke_test,
        :verification_smoke_tester,
        :dry_run,
        :overwrite_policy,
        :existence_checker,
        :tailwind_version,
        :tailwind_cli_version,
        :source_checksum,
        :release_fingerprint,
        :merge_manifest,
        :compose_targets,
        :manifest_merge_fetcher
      ])

    version = opts[:version] || raise ArgumentError, "version is required"
    source_path = opts[:source_path] || raise ArgumentError, "source_path is required"
    destination = opts[:destination] || :r2
    validate_binaries = Keyword.get(opts, :validate_binaries, true)
    smoke_test_binaries = Keyword.get(opts, :smoke_test_binaries, false)

    with {:find_binaries, {:ok, binaries}} <-
           {:find_binaries, find_distributable_binaries(source_path, version)},
         {:filter_binaries, {:ok, binaries}} <-
           {:filter_binaries, filter_binaries_for_deploy(binaries, version)},
         {:validate, :ok} <- {:validate, maybe_validate_binaries(binaries, validate_binaries)},
         {:smoke_test, {:ok, smoke_test_results}} <-
           {:smoke_test,
            maybe_smoke_test_binaries(
              binaries,
              version,
              smoke_test_binaries,
              Keyword.get(opts, :smoke_test_opts, [])
            )} do
      finish_deploy(binaries, %{
        version: version,
        destination: destination,
        dry_run: Keyword.get(opts, :dry_run, false),
        generate_manifest: Keyword.get(opts, :generate_manifest, true),
        generate_checksums: Keyword.get(opts, :generate_checksums, true),
        smoke_test_results: smoke_test_results,
        opts: opts
      })
    else
      {step, error} ->
        Logger.error("Deployment failed at step #{step}: #{inspect(error)}")
        {:error, {step, error}}
    end
  end

  # Resolve the overwrite/dry-run plan, then publish. Modes:
  #
  #   * `:dry_run`   — produce manifest + checksums locally, upload nothing.
  #   * `:upload`    — upload binaries, then verify, then publish metadata.
  #   * `:republish` — binaries already exist; regenerate metadata from local
  #     files and republish without re-uploading binaries (`:promote_only`).
  #
  # Metadata (`manifest.json`, `sha256sums.txt`) is only published after the
  # verify step succeeds in `:upload` mode.
  defp finish_deploy(binaries, ctx) do
    %{version: version, destination: destination, dry_run: dry_run, opts: opts} = ctx

    with {:plan, {:ok, mode}} <-
           {:plan, resolve_overwrite_plan(binaries, dry_run, opts, version)},
         {:deploy_binaries, {:ok, deployed}} <-
           {:deploy_binaries, run_deploy_mode(mode, binaries, destination, version, opts)},
         {:verify, {:ok, verification}} <-
           {:verify, maybe_verify_upload_for(mode, deployed, opts)},
         {:checksums, {:ok, sha256sums}} <-
           {:checksums, maybe_generate_sha256sums(deployed, ctx.generate_checksums)},
         {:manifest, {:ok, manifest}} <-
           {:manifest,
            maybe_generate_manifest(
              deployed,
              version,
              ctx.generate_manifest,
              Keyword.put(opts, :smoke_test_results, ctx.smoke_test_results)
            )},
         {:merge_metadata, {:ok, {manifest, sha256sums, extra_metadata}}} <-
           {:merge_metadata,
            maybe_merge_remote_metadata(mode, version, manifest, sha256sums, opts)},
         {:metadata_uploads, {:ok, metadata_uploads}} <-
           {:metadata_uploads,
            maybe_publish_metadata(
              mode,
              destination,
              version,
              manifest,
              sha256sums,
              extra_metadata,
              opts
            )} do
      {:ok,
       %{
         version: version,
         destination: destination,
         dry_run: dry_run,
         mode: mode,
         binaries_deployed: length(deployed),
         deployed_files: deployed,
         smoke_test_results: ctx.smoke_test_results,
         verification: verification,
         auxiliary_files: metadata_uploads,
         sha256sums: sha256sums,
         manifest: manifest
       }}
    else
      {step, error} ->
        Logger.error("Deployment failed at step #{step}: #{inspect(error)}")
        {:error, {step, error}}
    end
  end

  @doc """
  Decide the publish mode for a set of binaries given the overwrite policy.

  Returns `{:ok, :dry_run | :upload | :republish}` or an `{:error, reason}`
  tuple. Pure given an injected `:existence_checker`, so reruns are
  deterministic for tests.

  Policies:

    * `:overwrite` (default) — always `:upload`.
    * `:fail` — `:upload` only when no target artifact already exists, otherwise
      `{:error, {:artifacts_exist, names}}`.
    * `:promote_only` — `:republish` only when every target artifact already
      exists, otherwise `{:error, {:artifacts_missing, names}}`.
  """
  def resolve_overwrite_plan(binaries, dry_run \\ false, opts \\ [], version \\ nil)

  def resolve_overwrite_plan(_binaries, true, _opts, _version), do: {:ok, :dry_run}

  def resolve_overwrite_plan(binaries, false, opts, version) do
    case Keyword.get(opts, :overwrite_policy, :overwrite) do
      :overwrite ->
        {:ok, :upload}

      :fail ->
        case Enum.filter(binaries, &artifact_exists?(&1, opts, version)) do
          [] -> {:ok, :upload}
          existing -> {:error, {:artifacts_exist, Enum.map(existing, & &1.filename)}}
        end

      :promote_only ->
        case Enum.reject(binaries, &artifact_exists?(&1, opts, version)) do
          [] -> {:ok, :republish}
          missing -> {:error, {:artifacts_missing, Enum.map(missing, & &1.filename)}}
        end

      other ->
        {:error, {:invalid_overwrite_policy, other}}
    end
  end

  defp artifact_exists?(binary, opts, version) do
    checker = Keyword.get(opts, :existence_checker, &default_existence_checker/1)
    checker.(artifact_storage_url(binary, opts, version))
  end

  defp artifact_storage_url(binary, opts, version) do
    build_storage_url(artifact_remote_key(binary.filename, opts, version), opts)
  end

  defp artifact_remote_key(filename, opts, version) do
    prefix = Keyword.get(opts, :prefix, "tailwind_cli_daisyui")
    "#{prefix}/#{release_path(opts, version)}/#{filename}"
  end

  defp default_existence_checker(nil), do: false

  defp default_existence_checker(url) do
    case Req.head(url: url) do
      {:ok, %Req.Response{status: status}} -> status in 200..299
      _ -> false
    end
  rescue
    _ -> false
  end

  defp run_deploy_mode(:upload, binaries, destination, _version, opts) do
    deploy_binaries(binaries, destination, opts)
  end

  defp run_deploy_mode(mode, binaries, _destination, version, opts)
       when mode in [:dry_run, :republish] do
    {:ok, plan_local_deployed(binaries, opts, version)}
  end

  # Build the same `{:ok, deployed_info}` shape produced by a real upload, but
  # from local files only (no network), so manifest/checksum generation works
  # for dry-run and promote-only paths.
  defp plan_local_deployed(binaries, opts, version) do
    bucket = Keyword.get(opts, :bucket, "defdo")

    Enum.map(binaries, fn binary ->
      {:ok,
       %{
         local_path: binary.path,
         remote_key: artifact_remote_key(binary.filename, opts, version),
         bucket: bucket,
         size: binary.size
       }}
    end)
  end

  defp maybe_verify_upload_for(:upload, deployed, opts), do: maybe_verify_upload(deployed, opts)
  defp maybe_verify_upload_for(_mode, _deployed, _opts), do: {:ok, nil}

  defp maybe_publish_metadata(:dry_run, _destination, _version, _manifest, _sums, _extra, _opts) do
    {:ok, []}
  end

  defp maybe_publish_metadata(_mode, destination, version, manifest, sums, extra, opts) do
    maybe_upload_release_metadata(destination, version, manifest, sums, extra, opts)
  end

  @doc """
  Finds all distributable binaries in a directory
  """
  def find_distributable_binaries(source_path, version) do
    case get_dist_directory(source_path, version) do
      {:ok, dist_path} ->
        if File.exists?(dist_path) do
          binaries =
            Path.join(dist_path, "tailwindcss*")
            |> Path.wildcard()
            |> Enum.map(&get_binary_info/1)

          {:ok, binaries}
        else
          {:error, {:dist_directory_not_found, dist_path}}
        end

      error ->
        error
    end
  end

  @doc """
  Validates that binaries are ready for distribution
  """
  def validate_binaries(binaries) when is_list(binaries) do
    validation_results = Enum.map(binaries, &validate_single_binary/1)

    failed_validations =
      Enum.filter(validation_results, fn
        {:error, _} -> true
        _ -> false
      end)

    case failed_validations do
      [] -> :ok
      failures -> {:error, {:validation_failed, failures}}
    end
  end

  @doc """
  Uploads binaries to R2/S3
  """
  def deploy_to_r2(binaries, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, "defdo")
    prefix = Keyword.get(opts, :prefix, "tailwind_cli_daisyui")
    version = Keyword.get(opts, :version)
    release_path = release_path(opts, version)

    if version == nil do
      {:error, :version_required}
    else
      upload_results =
        Enum.map(binaries, fn binary ->
          deploy_single_binary_to_r2(binary, bucket, prefix, release_path)
        end)

      # Check if there were errors
      failures =
        Enum.filter(upload_results, fn
          {:error, _} -> true
          _ -> false
        end)

      case failures do
        [] -> {:ok, upload_results}
        _ -> {:error, {:upload_failures, failures}}
      end
    end
  end

  @doc """
  Generates a deployment manifest
  """
  @manifest_schema_version 1

  def generate_deployment_manifest(deployed_files, version, opts \\ []) do
    built_at = Keyword.get(opts, :built_at, DateTime.utc_now() |> DateTime.to_iso8601())
    compilation_info = Core.get_compilation_details(version)
    release_channel = Keyword.get(opts, :release_channel, "v#{version}")
    plugin_set = Keyword.get(opts, :plugin_set, [])
    tailwind_version = Keyword.get(opts, :tailwind_version, version)
    tailwind_cli_version = Keyword.get(opts, :tailwind_cli_version, version)
    release_fingerprint = Keyword.get(opts, :release_fingerprint)

    checks_by_target = build_checks_by_target(Keyword.get(opts, :smoke_test_results))

    file_opts =
      opts
      |> Keyword.put(:built_at, built_at)
      |> Keyword.put(:checks_by_target, checks_by_target)

    files = Enum.map(deployed_files, &format_file_info(&1, file_opts))

    manifest = %{
      manifest_schema_version: @manifest_schema_version,
      version: version,
      tailwind_version: tailwind_version,
      tailwind_cli_version: tailwind_cli_version,
      release_channel: release_channel,
      release_fingerprint: release_fingerprint,
      built_at: built_at,
      compilation_method: compilation_info.compilation_method,
      host_architecture: compilation_info.host_architecture,
      host_target_key: compilation_info.host_target_key,
      total_files: length(deployed_files),
      files: files,
      plugin_verification: summarize_plugin_verification(files),
      provenance: build_provenance(opts),
      metadata: %{
        cross_compilation_available: compilation_info.cross_compilation_available,
        supported_targets: compilation_info.supported_targets,
        supported_target_keys: compilation_info.compilable_target_keys,
        limitations: compilation_info.limitations,
        plugin_set: plugin_set
      },
      plugin_set: plugin_set
    }

    case Keyword.get(opts, :format, :map) do
      :json -> {:ok, Jason.encode!(manifest, pretty: true)}
      :map -> {:ok, manifest}
    end
  end

  @doc """
  Obtiene información detallada de un binario
  """
  def get_binary_info(file_path) when is_binary(file_path) do
    stat = File.stat!(file_path)

    %{
      path: file_path,
      filename: Path.basename(file_path),
      size: stat.size,
      size_mb: Float.round(stat.size / (1024 * 1024), 2),
      modified: stat.mtime,
      architecture: extract_architecture_from_filename(Path.basename(file_path)),
      executable: is_executable?(file_path)
    }
  end

  @doc """
  Generate sha256 sums for a list of deployed files
  """
  def generate_sha256_sums(deployed_files) when is_list(deployed_files) do
    lines =
      deployed_files
      |> Enum.flat_map(fn
        {:ok, deployed_info} ->
          filename = Path.basename(deployed_info.local_path)
          checksum = sha256_for_file!(deployed_info.local_path)
          ["#{checksum}  #{filename}"]

        _ ->
          []
      end)

    {:ok, Enum.join(lines, "\n")}
  end

  @doc """
  Verify uploaded artifacts by downloading each from its public storage URL and
  comparing the sha256 of the downloaded bytes against the local file checksum.

  This is the post-upload verification hook. When wired into `deploy/1` via the
  `:verify_upload` option, a verification failure aborts the pipeline before
  checksum files, manifest, and metadata are published.

  Options:

  - `:storage_base_url` - public base URL used to build each artifact URL.
  - `:verification_fetcher` - optional `(url -> {:ok, binary} | {:error, term})`
    used to download artifacts. Defaults to a Req-based fetcher. Inject this in
    tests to avoid hitting real storage.
  - `:verification_timeout` - per-request timeout in ms for the default fetcher
    (default `30_000`).

  Returns `{:ok, report}` when every artifact verifies, otherwise
  `{:error, {:verification_failed, report}}`, where `report` is:

      %{verified: non_neg_integer, failed: non_neg_integer, results: [map()]}

  Each result map contains `artifact_name`, `storage_url`, `status`
  (`:verified`, `:mismatch`, or `:fetch_failed`), `expected_sha256`,
  `actual_sha256` (or `nil`), and `error` (or `nil`).
  """
  def verify_uploaded_artifacts(deployed_files, opts \\ []) do
    fetcher = Keyword.get(opts, :verification_fetcher) || default_verification_fetcher(opts)

    results =
      deployed_files
      |> Enum.flat_map(fn
        {:ok, %{local_path: local_path, remote_key: remote_key}} ->
          [verify_one(local_path, remote_key, opts, fetcher)]

        _ ->
          []
      end)

    failed = Enum.filter(results, fn result -> result.status != :verified end)

    report = %{
      verified: length(results) - length(failed),
      failed: length(failed),
      results: results
    }

    if failed == [] do
      {:ok, report}
    else
      {:error, {:verification_failed, report}}
    end
  end

  @doc """
  Run a smoke test against a compiled Tailwind standalone binary
  """
  def smoke_test_binary(binary_path, opts \\ []) when is_binary(binary_path) do
    temp_dir =
      Path.join(System.tmp_dir!(), "tailwind_builder_smoke_#{System.unique_integer([:positive])}")

    input_css = Keyword.get(opts, :input_css, default_smoke_test_css())
    content_html = Keyword.get(opts, :content_html, default_smoke_test_content())
    expected_patterns = Keyword.get(opts, :expected_patterns, [".btn"])
    timeout = Keyword.get(opts, :timeout, 30_000)
    extra_args = Keyword.get(opts, :extra_args, ["--minify"])

    File.mkdir_p!(temp_dir)

    input_path = Path.join(temp_dir, "input.css")
    content_path = Path.join(temp_dir, "content.html")
    output_path = Path.join(temp_dir, "output.css")

    File.write!(input_path, input_css)
    File.write!(content_path, content_html)

    args = ["-i", Path.basename(input_path), "-o", Path.basename(output_path)] ++ extra_args

    task =
      Task.async(fn ->
        System.cmd(binary_path, args, cd: temp_dir, stderr_to_stdout: true)
      end)

    try do
      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {cli_output, 0}} ->
          with {:ok, output_css} <- File.read(output_path),
               :ok <- validate_smoke_test_output(output_css, expected_patterns) do
            {:ok,
             %{
               binary_path: binary_path,
               output_bytes: byte_size(output_css),
               matched_patterns: expected_patterns,
               cli_output: String.slice(cli_output, 0, 500)
             }}
          else
            {:error, reason} -> {:error, reason}
          end

        {:ok, {cli_output, exit_code}} ->
          {:error, {:command_failed, exit_code, String.slice(cli_output, 0, 500)}}

        nil ->
          {:error, :timeout}
      end
    after
      File.rm_rf(temp_dir)
    end
  end

  @doc """
  Runs a functional probe per plugin against a built binary and returns the
  per-plugin evidence. Each check is `:verified` (probe generated its marker),
  `:failed` (probe ran but the marker is missing), or `:unverified` (no probe is
  registered for the package). Fail-closed is the caller's job: any `:failed`
  check should fail the build.
  """
  @spec smoke_test_plugins(String.t(), [String.t()], keyword()) :: [map()]
  def smoke_test_plugins(binary_path, packages, opts \\ []) do
    Enum.map(packages, fn package ->
      case PluginProbes.probe_for(package) do
        nil ->
          %{plugin: package, status: :unverified}

        %{content: content, expected: expected} ->
          probe_opts =
            opts
            |> Keyword.put(:input_css, PluginProbes.input_css(package))
            |> Keyword.put(:content_html, "<div>#{content}</div>")
            |> Keyword.put(:expected_patterns, expected)

          case smoke_test_binary(binary_path, probe_opts) do
            {:ok, result} ->
              %{plugin: package, status: :verified, expected: expected, output_bytes: result.output_bytes}

            {:error, reason} ->
              %{plugin: package, status: :failed, expected: expected, reason: inspect(reason)}
          end
      end
    end)
  end

  @doc """
  Extract npm package names from a plugin_set (maps or `key=name@ver`/`name@ver`
  strings), for probe lookup.
  """
  @spec plugin_packages(list()) :: [String.t()]
  def plugin_packages(plugin_set) when is_list(plugin_set) do
    plugin_set
    |> Enum.map(&plugin_package/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  def plugin_packages(_), do: []

  defp plugin_package(%{} = entry) do
    entry["npm_source"] || entry["name"] || entry[:npm_source] || entry[:name]
  end

  defp plugin_package(entry) when is_binary(entry) do
    # "daisyui_v5=daisyui@5.6.10" -> "daisyui"; "daisyui@5.6.10" -> "daisyui".
    name_ver = entry |> String.split("=", parts: 2) |> List.last()
    idx = :binary.matches(name_ver, "@") |> List.last()

    case idx do
      {pos, _} when pos > 0 -> binary_part(name_ver, 0, pos)
      _ -> name_ver
    end
  end

  defp plugin_package(_), do: nil

  @doc """
  Verifica si un archivo es ejecutable
  """
  def is_executable?(file_path) do
    case File.stat(file_path) do
      {:ok, %{mode: mode}} ->
        # Verificar si tiene permisos de ejecución
        import Bitwise
        (mode &&& 0o111) != 0

      _ ->
        false
    end
  end

  # Funciones privadas

  defp maybe_validate_binaries(binaries, true), do: validate_binaries(binaries)
  defp maybe_validate_binaries(_binaries, false), do: :ok

  defp maybe_generate_manifest(deployed_files, version, true, opts) do
    generate_deployment_manifest(deployed_files, version, opts)
  end

  defp maybe_generate_manifest(_deployed_files, _version, false, _opts), do: {:ok, nil}

  defp maybe_generate_sha256sums(deployed_files, true) do
    generate_sha256_sums(deployed_files)
  end

  defp maybe_generate_sha256sums(_deployed_files, false), do: {:ok, nil}

  # Merge this run's single-target manifest + checksums with any manifest already
  # published to the same channel, so multi-arch builds that publish to one
  # channel accumulate into a single multi-target manifest instead of
  # overwriting each other.
  #
  # New entries win on filename collision; the latest build's top-level
  # provenance/built_at is kept. `sha256sums.txt` is regenerated from the merged
  # file list so the manifest and checksums always agree.
  #
  # Skipped for dry-run, when disabled via `merge_manifest: false`, or when there
  # is no manifest to merge.
  @file_keys ~w(filename artifact_name target_key build_target remote_key storage_url checksum_sha256 size_bytes size_mb built_at architecture status plugin_set plugin_checks release_fingerprint)a
  @plugin_keys ~w(name version plugin_key)a

  # Returns `{:ok, {manifest, sha256sums, extra_files}}` where `extra_files` is a
  # list of `{filename, content}` to publish alongside `manifest.json`/
  # `sha256sums.txt` (used to publish the per-arch fragment).
  #
  # Strategy precedence:
  #   * `compose_targets` set  → fragment + compose (race-free; preferred for CI).
  #   * `merge_manifest` (default true) → read-modify-write merge of the channel
  #     `manifest.json` (best-effort; fine for single-writer / serial runs).
  #   * neither → publish this run's single-target manifest as-is.
  defp maybe_merge_remote_metadata(:dry_run, _version, manifest, sums, _opts),
    do: {:ok, {manifest, sums, []}}

  defp maybe_merge_remote_metadata(_mode, _version, nil, sums, _opts), do: {:ok, {nil, sums, []}}

  defp maybe_merge_remote_metadata(_mode, version, manifest, sums, opts) do
    cond do
      is_list(Keyword.get(opts, :compose_targets)) ->
        compose_channel_metadata(version, manifest, sums, opts)

      Keyword.get(opts, :merge_manifest, true) ->
        with {:ok, {merged, merged_sums}} <-
               do_merge_remote_metadata(version, manifest, sums, opts) do
          {:ok, {merged, merged_sums, []}}
        end

      true ->
        {:ok, {manifest, sums, []}}
    end
  end

  defp do_merge_remote_metadata(version, manifest, sums, opts) do
    case fetch_remote_manifest(version, opts) do
      {:ok, remote} ->
        {merged, merged_sums} = merge_published_manifest(remote, manifest)
        {:ok, {merged, merged_sums || sums}}

      :none ->
        {:ok, {manifest, sums}}

      {:error, reason} ->
        Logger.warning(
          "Manifest merge skipped: could not fetch remote manifest (#{inspect(reason)}); " <>
            "publishing this run's manifest as-is"
        )

        {:ok, {manifest, sums}}
    end
  end

  # Race-free channel manifest: publish this run's single-target manifest as an
  # immutable per-arch fragment (`manifest.d/<target_key>.json`, written only by
  # this arch), then compose the channel `manifest.json` by folding this run with
  # the sibling fragments named in `compose_targets`. Because fragments are
  # single-writer, concurrent composes converge monotonically to the full set,
  # and any later run deterministically reconstructs the complete manifest from
  # fragments. Missing siblings (not built yet) are skipped, not an error.
  defp compose_channel_metadata(version, manifest, sums, opts) do
    self_target = manifest_target_key(manifest)
    fragment = {fragment_filename(self_target), Jason.encode!(manifest, pretty: true)}

    siblings =
      opts
      |> Keyword.get(:compose_targets, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == self_target))
      |> Enum.flat_map(fn target ->
        case fetch_fragment(version, target, opts) do
          {:ok, sibling} ->
            [sibling]

          :none ->
            []

          {:error, reason} ->
            Logger.warning("Compose skipped sibling fragment #{target}: #{inspect(reason)}")

            []
        end
      end)

    composed = compose_manifest(manifest, siblings)
    composed_sums = sha256sums_from_manifest(composed) || sums
    {:ok, {composed, composed_sums, [fragment]}}
  end

  @doc """
  Compose a channel manifest by folding this run's manifest with sibling
  per-arch manifests. This run wins on `filename` collision (it owns its target);
  siblings contribute their distinct targets. Order-independent for distinct
  targets. Pure — no network.
  """
  @spec compose_manifest(map(), [map()]) :: map()
  def compose_manifest(base, siblings) when is_map(base) and is_list(siblings) do
    Enum.reduce(siblings, base, fn sibling, acc -> merge_manifests(sibling, acc) end)
  end

  defp fragment_filename(target_key), do: "manifest.d/#{target_key || "unknown"}.json"

  defp manifest_target_key(manifest) do
    manifest
    |> manifest_files()
    |> List.first()
    |> case do
      nil -> nil
      file -> fetch_any(file, :target_key) || fetch_any(file, :filename)
    end
  end

  defp fetch_fragment(version, target_key, opts) do
    url = build_storage_url(fragment_remote_key(target_key, opts, version), opts)

    if is_nil(url) do
      :none
    else
      fetcher = Keyword.get(opts, :manifest_merge_fetcher) || (&default_manifest_merge_fetcher/1)

      case fetcher.(url) do
        {:ok, body} when is_map(body) -> {:ok, body}
        {:ok, body} when is_binary(body) -> decode_remote_manifest(body)
        :not_found -> :none
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fragment_remote_key(target_key, opts, version) do
    artifact_remote_key(fragment_filename(target_key), opts, version)
  end

  defp fetch_remote_manifest(version, opts) do
    case remote_manifest_url(version, opts) do
      nil ->
        :none

      url ->
        fetcher =
          Keyword.get(opts, :manifest_merge_fetcher) || (&default_manifest_merge_fetcher/1)

        case fetcher.(url) do
          {:ok, body} when is_map(body) -> {:ok, body}
          {:ok, body} when is_binary(body) -> decode_remote_manifest(body)
          :not_found -> :none
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp decode_remote_manifest(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_remote_manifest}
    end
  end

  defp remote_manifest_url(version, opts) do
    build_storage_url(artifact_remote_key("manifest.json", opts, version), opts)
  end

  defp default_manifest_merge_fetcher(url) do
    case Req.get(url: url) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 404}} -> :not_found
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  @doc """
  Merge a previously published channel manifest with this run's manifest.

  Returns `{merged_manifest, sha256sums_text}`. Remote file and plugin entries
  are preserved unless this run publishes the same `filename`/`plugin_key`, in
  which case the local entry wins. `total_files` is recomputed and
  `sha256sums_text` is regenerated from the merged file list so the manifest and
  checksums always agree. Pure — performs no network access. Accepts maps with
  either atom keys (locally generated) or string keys (decoded remote JSON).
  """
  @spec merge_published_manifest(map(), map()) :: {map(), String.t() | nil}
  def merge_published_manifest(remote, local) when is_map(remote) and is_map(local) do
    merged = merge_manifests(remote, local)
    {merged, sha256sums_from_manifest(merged)}
  end

  defp merge_manifests(remote, local) do
    local_fingerprint = fetch_any(local, :release_fingerprint)

    remote_files =
      remote
      |> manifest_files()
      |> Enum.map(&normalize_keyed(&1, @file_keys))
      |> Enum.filter(&same_release_fingerprint?(&1, local_fingerprint))

    local_files = Enum.map(manifest_files(local), &normalize_keyed(&1, @file_keys))
    local_keys = MapSet.new(local_files, &file_key/1)

    merged_files =
      Enum.reject(remote_files, &MapSet.member?(local_keys, file_key(&1))) ++ local_files

    merged_plugins = merge_plugin_sets(remote, local)

    local
    |> Map.put(:files, merged_files)
    |> Map.put(:total_files, length(merged_files))
    |> Map.put(:plugin_set, merged_plugins)
    |> put_metadata_plugin_set(merged_plugins)
  end

  defp merge_plugin_sets(remote, local) do
    remote_plugins = Enum.map(manifest_plugin_set(remote), &normalize_keyed(&1, @plugin_keys))
    local_plugins = Enum.map(manifest_plugin_set(local), &normalize_keyed(&1, @plugin_keys))
    local_keys = MapSet.new(local_plugins, &plugin_key/1)

    Enum.reject(remote_plugins, &MapSet.member?(local_keys, plugin_key(&1))) ++ local_plugins
  end

  defp put_metadata_plugin_set(%{metadata: %{} = meta} = manifest, plugins),
    do: Map.put(manifest, :metadata, Map.put(meta, :plugin_set, plugins))

  defp put_metadata_plugin_set(manifest, _plugins), do: manifest

  defp sha256sums_from_manifest(manifest) do
    lines =
      manifest
      |> manifest_files()
      |> Enum.flat_map(fn file ->
        name = fetch_any(file, :filename)
        sum = fetch_any(file, :checksum_sha256)
        if name && sum, do: ["#{sum}  #{name}"], else: []
      end)
      |> Enum.sort()

    case lines do
      [] -> nil
      _ -> Enum.join(lines, "\n")
    end
  end

  defp manifest_files(manifest), do: fetch_any(manifest, :files) || []
  defp manifest_plugin_set(manifest), do: fetch_any(manifest, :plugin_set) || []

  defp file_key(file), do: fetch_any(file, :filename) || fetch_any(file, :target_key)
  defp plugin_key(plugin), do: fetch_any(plugin, :plugin_key) || fetch_any(plugin, :name)

  defp same_release_fingerprint?(_file, nil), do: true

  defp same_release_fingerprint?(file, fingerprint),
    do: fetch_any(file, :release_fingerprint) == fingerprint

  # JSON fetched from storage has string keys; locally generated maps have atom
  # keys. Normalize a single entry to atom keys over a fixed, known key set so we
  # never call String.to_atom on untrusted remote input.
  defp normalize_keyed(entry, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case fetch_any(entry, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp fetch_any(map, atom_key) when is_map(map) do
    case Map.get(map, atom_key) do
      nil -> Map.get(map, Atom.to_string(atom_key))
      value -> value
    end
  end

  defp fetch_any(_map, _atom_key), do: nil

  defp maybe_verify_upload(deployed, opts) do
    if Keyword.get(opts, :verify_upload, false) do
      verify_uploaded_artifacts(deployed, opts)
    else
      {:ok, nil}
    end
  end

  defp verify_one(local_path, remote_key, opts, fetcher) do
    expected = sha256_for_file!(local_path)
    url = build_storage_url(remote_key, opts)

    result = %{
      artifact_name: Path.basename(local_path),
      storage_url: url,
      status: :fetch_failed,
      expected_sha256: expected,
      actual_sha256: nil,
      error: nil
    }

    cond do
      is_nil(url) ->
        %{result | error: {:missing_storage_base_url, nil}}

      true ->
        case fetcher.(url) do
          {:ok, body} ->
            actual = sha256_for_bytes(body)

            if actual == expected do
              maybe_smoke_verify(%{result | status: :verified, actual_sha256: actual}, body, opts)
            else
              %{result | status: :mismatch, actual_sha256: actual}
            end

          {:error, reason} ->
            %{result | error: reason}
        end
    end
  end

  # When `:verify_smoke_test` is enabled, the checksum-verified download is
  # written to a temp file and smoke tested. A smoke failure downgrades the
  # result to `:smoke_failed`, which `verify_uploaded_artifacts/2` counts as a
  # failure and which aborts metadata publication.
  defp maybe_smoke_verify(result, body, opts) do
    if Keyword.get(opts, :verify_smoke_test, false) do
      tester =
        Keyword.get(opts, :verification_smoke_tester, &default_downloaded_smoke_tester(&1, opts))

      case run_downloaded_smoke(body, tester) do
        {:ok, _info} ->
          Map.put(result, :smoke_test, :passed)

        {:error, reason} ->
          %{result | status: :smoke_failed, error: reason} |> Map.put(:smoke_test, :failed)
      end
    else
      result
    end
  end

  defp run_downloaded_smoke(body, tester) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "tailwind_builder_verify_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "tailwindcss")
    File.write!(path, body)
    File.chmod!(path, 0o755)

    try do
      tester.(path)
    after
      File.rm_rf(dir)
    end
  end

  defp default_downloaded_smoke_tester(path, opts) do
    smoke_test_binary(path, Keyword.get(opts, :smoke_test_opts, []))
  end

  defp default_verification_fetcher(opts) do
    timeout = Keyword.get(opts, :verification_timeout, 30_000)

    fn url -> httpc_get(url, timeout) end
  end

  # Verification downloads use :httpc, not Req/Finch.
  #
  # Inside the release flow (verify runs after the R2 uploads), Req.get of the
  # uploaded multi-MB binary raises `:ssl.recv/3` "no function clause" on OTP 28
  # — deterministically, on every attempt. Reproduced on mint 1.9.0 / finch
  # 0.23.0; bumping those deps and retrying the request did not help (3/3 raised).
  # OTP 28's :ssl.recv/3 rejects the `nil` timeout that Mint passes on this path.
  # :httpc downloads the same artifact reliably in the same context.
  #
  # This path only needs to GET public bytes and hash them, so Req's extra
  # features (redirects, auth, pooling) are not required. Transport integrity is
  # not relied on either: the caller compares the sha256 of the returned bytes
  # against the local artifact, so a tampered/truncated body fails verification.
  defp httpc_get(url, timeout) do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)

    http_opts = [timeout: timeout, connect_timeout: timeout]
    request = {String.to_charlist(url), []}

    case :httpc.request(:get, request, http_opts, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, body}} when status in 200..299 ->
        {:ok, body}

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sha256_for_bytes(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end

  defp maybe_smoke_test_binaries(_binaries, _version, false, _opts), do: {:ok, nil}

  defp maybe_smoke_test_binaries(binaries, version, true, opts) do
    host = Core.get_host_architecture()

    runnable_binaries =
      Enum.filter(binaries, fn b -> match_architecture?(Map.get(b, :architecture), host) end)

    Logger.info(
      "Smoke test: host=#{host} binaries=#{inspect(Enum.map(binaries, &Map.get(&1, :architecture)))} runnable=#{length(runnable_binaries)}"
    )

    cond do
      runnable_binaries == [] ->
        Logger.warning(
          "Smoke test SKIPPED: no runnable binary matches host #{host} — plugin verification will be empty"
        )

        {:ok, %{tested: 0, skipped: length(binaries), results: []}}

      String.starts_with?(version, "4.") or Keyword.has_key?(opts, :input_css) ->
        packages = plugin_packages(Keyword.get(opts, :plugin_set, []))

        results =
          Enum.map(runnable_binaries, fn binary_info ->
            checks =
              if packages == [] do
                # No plugins declared — fall back to the base Tailwind probe.
                case smoke_test_binary(binary_info.path, opts) do
                  {:ok, _} -> [%{plugin: "tailwindcss", status: :verified}]
                  {:error, reason} -> [%{plugin: "tailwindcss", status: :failed, reason: inspect(reason)}]
                end
              else
                smoke_test_plugins(binary_info.path, packages, opts)
              end

            %{target_key: Map.get(binary_info, :target_key), checks: checks}
          end)

        Logger.info(
          "Smoke test plugin checks: #{inspect(Enum.flat_map(results, & &1.checks))}"
        )

        # Fail-closed: any plugin whose registered probe did not generate its
        # marker fails the whole deploy (the binary is never published).
        failures =
          results
          |> Enum.flat_map(& &1.checks)
          |> Enum.filter(&(&1.status == :failed))

        case failures do
          [] ->
            {:ok,
             %{
               tested: length(runnable_binaries),
               skipped: length(binaries) - length(runnable_binaries),
               results: results
             }}

          _ ->
            {:error, {:smoke_test_failed, failures}}
        end

      true ->
        {:ok,
         %{
           tested: 0,
           skipped: length(binaries),
           results: [],
           reason: :no_default_smoke_test_for_version
         }}
    end
  end

  defp filter_binaries_for_deploy(binaries, version) do
    case Core.get_version_constraints(version) do
      %{major_version: :v4} ->
        host_arch = Core.get_host_architecture()

        filtered =
          Enum.filter(binaries, fn %{architecture: arch} ->
            match_architecture?(arch, host_arch)
          end)

        case filtered do
          [] -> {:error, {:no_binaries_for_host, host_arch}}
          list -> {:ok, list}
        end

      _ ->
        {:ok, binaries}
    end
  end

  defp get_dist_directory(source_path, version) do
    case Core.get_version_constraints(version) do
      %{major_version: :v3} ->
        dist_path = Path.join([source_path, "tailwindcss-#{version}", "standalone-cli", "dist"])
        {:ok, dist_path}

      %{major_version: :v4} ->
        dist_path =
          Path.join([
            source_path,
            "tailwindcss-#{version}",
            "packages",
            "@tailwindcss-standalone",
            "dist"
          ])

        {:ok, dist_path}

      _ ->
        {:error, :unsupported_version}
    end
  end

  defp validate_single_binary(binary_info) do
    cond do
      # Menos de 10 bytes parece muy pequeño (se permiten archivos de test)
      binary_info.size < 10 ->
        {:error, {:file_too_small, binary_info.filename}}

      # Más de 500MB parece muy grande (TailwindCSS v4.x puede ser más grande)
      binary_info.size > 500_000_000 ->
        {:error, {:file_too_large, binary_info.filename}}

      true ->
        {:ok, binary_info}
    end
  end

  defp deploy_binaries(binaries, :r2, opts) do
    deploy_to_r2(binaries, opts)
  end

  defp deploy_binaries(binaries, :s3, opts) do
    # Same implementation
    deploy_to_r2(binaries, opts)
  end

  defp deploy_binaries(_binaries, destination, _opts) do
    {:error, {:unsupported_destination, destination}}
  end

  defp deploy_single_binary_to_r2(binary_info, bucket, prefix, release_path) do
    filename = binary_info.filename
    object_key = "#{prefix}/#{release_path}/#{filename}"

    Logger.info("Uploading #{filename} to #{bucket}/#{object_key}")

    try do
      req = storage_req()

      # Read file and upload using the s3 operation
      file_content = File.read!(binary_info.path)

      result = Req.put!(req, url: "/#{bucket}/#{object_key}", body: file_content)

      if result.status in 200..299 do
        Logger.info("Successfully uploaded #{filename}")

        {:ok,
         %{
           local_path: binary_info.path,
           remote_key: object_key,
           bucket: bucket,
           size: binary_info.size,
           upload_result: %{status: result.status, headers: result.headers}
         }}
      else
        raise "Upload failed with status #{result.status}"
      end
    rescue
      error ->
        Logger.error("Failed to upload #{filename}: #{inspect(error)}")
        {:error, {:upload_failed, filename, error}}
    end
  end

  defp extract_architecture_from_filename(filename) do
    Targets.target_key_from_filename(filename) || "unknown"
  end

  # Canonical build target for a known target_key, nil for "unknown".
  defp build_target_for(target_key) do
    case Targets.build_target(target_key) do
      build_target when is_binary(build_target) -> build_target
      _ -> nil
    end
  end

  defp match_architecture?("unknown", _host), do: false

  defp match_architecture?(binary_arch, host_arch) do
    Targets.matches?(binary_arch, host_arch)
  end

  defp format_file_info({:ok, deployed_info}, opts) do
    filename = Path.basename(deployed_info.local_path)
    target_key = extract_architecture_from_filename(filename)
    checksum = sha256_for_file!(deployed_info.local_path)

    %{
      filename: filename,
      artifact_name: filename,
      target_key: target_key,
      build_target: build_target_for(target_key),
      remote_key: deployed_info.remote_key,
      storage_url: build_storage_url(deployed_info.remote_key, opts),
      checksum_sha256: checksum,
      size_bytes: deployed_info.size,
      size_mb: Float.round(deployed_info.size / (1024 * 1024), 2),
      built_at: Keyword.get(opts, :built_at),
      architecture: target_key,
      plugin_set: Keyword.get(opts, :plugin_set, []),
      plugin_checks: checks_for(target_key, opts),
      release_fingerprint: Keyword.get(opts, :release_fingerprint)
    }
  end

  defp format_file_info({:error, {_step, filename, _error}}, _opts) do
    %{
      filename: filename,
      status: "failed",
      error: "upload_failed"
    }
  end

  # Handle raw binary info maps (for direct usage from tests/external calls)
  defp format_file_info(%{filename: filename, size: size} = binary_info, opts)
       when is_map(binary_info) do
    target_key = extract_architecture_from_filename(filename)

    %{
      filename: filename,
      artifact_name: filename,
      target_key: target_key,
      # Not deployed yet
      remote_key: nil,
      storage_url: build_storage_url(binary_info[:remote_key], opts),
      checksum_sha256: binary_info[:checksum_sha256],
      size_bytes: size,
      size_mb: Float.round(size / (1024 * 1024), 2),
      architecture: target_key,
      plugin_set: Keyword.get(opts, :plugin_set, []),
      plugin_checks: checks_for(target_key, opts),
      release_fingerprint: Keyword.get(opts, :release_fingerprint),
      status: "pending"
    }
  end

  # Per-plugin functional evidence for a target, from the smoke-test results.
  defp checks_for(target_key, opts) do
    opts |> Keyword.get(:checks_by_target, %{}) |> Map.get(target_key, [])
  end

  defp build_checks_by_target(%{results: results}) when is_list(results) do
    Map.new(results, fn r -> {Map.get(r, :target_key), Map.get(r, :checks, [])} end)
  end

  defp build_checks_by_target(_), do: %{}

  # Overall plugin-verification for the manifest: verified when every probe
  # generated its marker, unverified when a plugin has no probe, failed if any
  # probe missed (fail-closed should prevent publish, but record it defensively).
  defp summarize_plugin_verification(files) do
    checks = Enum.flat_map(files, fn f -> Map.get(f, :plugin_checks) || [] end)
    statuses = checks |> Enum.map(& &1.status) |> Enum.uniq()

    status =
      cond do
        :failed in statuses -> :failed
        :unverified in statuses -> :unverified
        checks == [] -> :unknown
        true -> :verified
      end

    %{status: status, checks: checks}
  end

  defp maybe_upload_release_metadata(_destination, _version, nil, nil, [], _opts), do: {:ok, []}

  defp maybe_upload_release_metadata(destination, version, manifest, sha256sums, extra, opts)
       when destination in [:r2, :s3] do
    bucket = Keyword.get(opts, :bucket, "defdo")
    prefix = Keyword.get(opts, :prefix, "tailwind_cli_daisyui")
    release_path = release_path(opts, version)

    uploads =
      [
        manifest && {"manifest.json", Jason.encode!(manifest, pretty: true)},
        sha256sums && {"sha256sums.txt", ensure_trailing_newline(sha256sums)}
      ]
      |> Kernel.++(List.wrap(extra))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn {filename, content} ->
        upload_content_to_r2(content, filename, bucket, prefix, release_path)
      end)

    failures =
      Enum.filter(uploads, fn
        {:error, _reason} -> true
        _ -> false
      end)

    case failures do
      [] -> {:ok, uploads}
      _ -> {:error, {:metadata_upload_failures, failures}}
    end
  end

  defp maybe_upload_release_metadata(
         _destination,
         _version,
         _manifest,
         _sha256sums,
         _extra,
         _opts
       ) do
    {:ok, []}
  end

  defp default_smoke_test_css do
    """
    @import "tailwindcss";
    @source "./content.html";
    @plugin "daisyui";
    """
  end

  defp default_smoke_test_content do
    ~s(<button class="btn btn-primary">Smoke test</button>)
  end

  defp validate_smoke_test_output(output_css, expected_patterns) do
    trimmed_output = String.trim(output_css)

    cond do
      trimmed_output == "" ->
        {:error, :empty_output}

      Enum.any?(expected_patterns, &(not String.contains?(trimmed_output, &1))) ->
        {:error, {:missing_expected_patterns, expected_patterns}}

      true ->
        :ok
    end
  end

  defp sha256_for_file!(path) do
    path |> File.read!() |> sha256_for_bytes()
  end

  # Build provenance from values observable on the local builder host. Any tool
  # that is not installed resolves to nil instead of failing the manifest.
  defp build_provenance(opts) do
    {os_family, os_name} = :os.type()

    %{
      hostname: provenance_hostname(),
      os: "#{os_family}/#{os_name}",
      arch: Core.get_host_architecture(),
      elixir_version: System.version(),
      otp_release: List.to_string(:erlang.system_info(:otp_release)),
      node_version: tool_version("node", ["--version"]),
      rust_version: tool_version("rustc", ["--version"]),
      bun_version: tool_version("bun", ["--version"]),
      pnpm_version: tool_version("pnpm", ["--version"]),
      source_checksum: Keyword.get(opts, :source_checksum),
      git_sha: git_sha()
    }
  end

  defp provenance_hostname do
    case :inet.gethostname() do
      {:ok, host} -> List.to_string(host)
      _ -> nil
    end
  end

  defp tool_version(executable, args) do
    case System.find_executable(executable) do
      nil ->
        nil

      path ->
        try do
          case System.cmd(path, args, stderr_to_stdout: true) do
            {output, 0} -> output |> String.trim() |> first_line()
            _ -> nil
          end
        rescue
          _ -> nil
        end
    end
  end

  defp git_sha do
    case System.find_executable("git") do
      nil ->
        nil

      path ->
        try do
          case System.cmd(path, ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
            {output, 0} -> String.trim(output)
            _ -> nil
          end
        rescue
          _ -> nil
        end
    end
  end

  defp first_line(string) do
    string |> String.split("\n", parts: 2) |> hd()
  end

  defp build_storage_url(nil, _opts), do: nil

  defp build_storage_url(remote_key, opts) do
    case Keyword.get(opts, :storage_base_url) do
      nil ->
        nil

      base_url ->
        normalized_base = String.trim_trailing(base_url, "/")
        "#{normalized_base}/#{remote_key}"
    end
  end

  defp upload_content_to_r2(content, filename, bucket, prefix, release_path) do
    object_key = "#{prefix}/#{release_path}/#{filename}"

    try do
      req = storage_req()
      result = Req.put!(req, url: "/#{bucket}/#{object_key}", body: content)

      if result.status in 200..299 do
        {:ok,
         %{
           filename: filename,
           remote_key: object_key,
           size_bytes: byte_size(content),
           upload_result: %{status: result.status, headers: result.headers}
         }}
      else
        raise "Upload failed with status #{result.status}"
      end
    rescue
      error ->
        {:error, {:upload_failed, filename, error}}
    end
  end

  @doc """
  Normalize a storage host value by stripping any protocol prefix.

  Accepts both `example.r2.cloudflarestorage.com` and
  `https://example.r2.cloudflarestorage.com`, returning only the
  bare host.
  """
  def normalize_storage_host(host) when is_binary(host) do
    host
    |> String.replace(~r{^https?://}, "")
    |> String.trim_trailing("/")
  end

  def normalize_storage_host(nil), do: nil

  # Default receive timeout (ms) for storage uploads. Large standalone binaries
  # (tens to >100 MB) over a slow link can exceed Req's default receive timeout
  # and surface as `%Req.TransportError{reason: :timeout}` even though the object
  # uploaded. A generous default avoids spurious upload failures.
  @default_upload_timeout 300_000

  @doc """
  Resolve the receive timeout (ms) used for storage uploads.

  Reads `:upload_timeout` from the `:tailwind_builder, :storage` app config when
  present, otherwise falls back to `#{@default_upload_timeout}` ms. The `/1`
  arity is pure given an explicit config and is the unit-tested surface.
  """
  def resolve_upload_timeout do
    resolve_upload_timeout(Application.get_env(:tailwind_builder, :storage))
  end

  def resolve_upload_timeout(config) when is_list(config) do
    config[:upload_timeout] || @default_upload_timeout
  end

  def resolve_upload_timeout(_config), do: @default_upload_timeout

  defp storage_req do
    storage_config = Application.get_env(:tailwind_builder, :storage) || []
    access_key_id = storage_config[:access_key_id]
    secret_access_key = storage_config[:secret_access_key]
    host = normalize_storage_host(storage_config[:host])
    region = storage_config[:region] || "auto"

    Req.new(base_url: "https://#{host}", receive_timeout: resolve_upload_timeout())
    |> ReqS3.attach(
      aws_sigv4: [
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        region: region,
        service: "s3"
      ]
    )
  end

  defp release_path(opts, version) do
    Keyword.get(opts, :release_channel, "v#{version}")
  end

  defp ensure_trailing_newline(value) do
    if String.ends_with?(value, "\n"), do: value, else: value <> "\n"
  end

  @doc """
  Promote a published channel from one R2 prefix to another (e.g. the CI canary
  prefix to the production prefix) WITHOUT rebuilding.

  Binaries and `sha256sums.txt` are copied server-side (S3 CopyObject — the exact
  verified bytes, no download). `manifest.json` and each `manifest.d/<target>.json`
  fragment are fetched, their prefix references rewritten to the destination, and
  re-uploaded, so the promoted manifest is self-consistent.

  Options:
    * `:channel` (required) — e.g. `"v4.3.2-rc1"`. Same dir name on both sides.
    * `:source_prefix` — default `"tailwind_cli_daisyui_ci_canary"` (canary).
    * `:dest_prefix` — default `"tailwind_cli_daisyui"` (production).
    * `:bucket` — default `"defdo"`.
    * `:storage_base_url` — default `"https://storage.defdo.de"`.
    * `:fetcher` — `(url -> {:ok, body} | {:error, term})`, injectable for tests.

  R2 credentials are read from `config :tailwind_builder, :storage` (same as the
  release upload path).
  """
  @spec promote_channel(keyword()) :: {:ok, map()} | {:error, term()}
  def promote_channel(opts) do
    channel = Keyword.fetch!(opts, :channel)
    # Production channels follow the upstream Tailwind release tag exactly (e.g.
    # v4.3.2) — only the domain + path prefix differ from tailwindlabs' URLs.
    # The canary pre-release suffix (v4.3.2-rc1) is dropped on promotion.
    dst_channel = Keyword.get(opts, :dest_channel, prod_channel(channel))
    bucket = Keyword.get(opts, :bucket, "defdo")
    src_prefix = Keyword.get(opts, :source_prefix, "tailwind_cli_daisyui_ci_canary")
    dst_prefix = Keyword.get(opts, :dest_prefix, "tailwind_cli_daisyui")
    base_url = Keyword.get(opts, :storage_base_url, "https://storage.defdo.de")
    fetcher = Keyword.get(opts, :fetcher, &default_promote_fetch/1)

    src_manifest_url = "#{base_url}/#{src_prefix}/#{channel}/manifest.json"

    with {:ok, manifest} <- fetcher.(src_manifest_url),
         {:ok, decoded} <- decode_manifest(manifest) do
      req = storage_req()
      files = decoded["files"] || []
      target_keys = files |> Enum.map(& &1["target_key"]) |> Enum.reject(&is_nil/1)

      binary_names = Enum.map(files, & &1["filename"]) ++ ["sha256sums.txt"]
      json_names = ["manifest.json" | Enum.map(target_keys, &"manifest.d/#{&1}.json")]

      with :ok <-
             copy_objects(req, bucket, src_prefix, dst_prefix, channel, dst_channel, binary_names),
           :ok <-
             rewrite_jsons(
               req,
               fetcher,
               base_url,
               bucket,
               src_prefix,
               dst_prefix,
               channel,
               dst_channel,
               json_names
             ) do
        {:ok,
         %{
           channel: dst_channel,
           source_channel: channel,
           promoted_files: length(files),
           manifest_url: "#{base_url}/#{dst_prefix}/#{dst_channel}/manifest.json"
         }}
      end
    end
  end

  # Strip a canary pre-release suffix (-rc1, -beta2, …) so production uses the
  # bare Tailwind release tag; leave already-bare tags untouched.
  defp prod_channel(channel), do: Regex.replace(~r/-(rc|beta|alpha)\d*$/i, channel, "")

  @doc """
  Lists the published channel/version directories directly under an R2 `prefix`
  (via S3 ListObjectsV2 with a `/` delimiter), e.g. `["v4.2.2", "v4.3.2-rc1"]`.
  """
  @spec list_published_channels(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def list_published_channels(prefix, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, "defdo")
    req = storage_req()

    case Req.get(req,
           url: "/#{bucket}",
           params: %{"list-type" => "2", "prefix" => "#{prefix}/", "delimiter" => "/"},
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, parse_common_prefixes(body, prefix)}
      {:ok, %{status: status}} -> {:error, {:list_failed, status}}
      {:error, reason} -> {:error, {:list_failed, reason}}
    end
  end

  defp parse_common_prefixes(body, prefix) do
    xml = to_string_body(body)

    ~r{<Prefix>#{Regex.escape(prefix)}/([^/<]+)/</Prefix>}
    |> Regex.scan(xml)
    |> Enum.map(fn [_, version] -> version end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp decode_manifest(manifest) when is_map(manifest), do: {:ok, manifest}
  defp decode_manifest(manifest) when is_binary(manifest), do: Jason.decode(manifest)
  defp decode_manifest(_), do: {:error, :invalid_manifest}

  defp copy_objects(req, bucket, src_prefix, dst_prefix, src_channel, dst_channel, names) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      src = "/#{bucket}/#{src_prefix}/#{src_channel}/#{name}"
      dst = "/#{bucket}/#{dst_prefix}/#{dst_channel}/#{name}"

      case Req.put(req, url: dst, headers: [{"x-amz-copy-source", src}]) do
        {:ok, %{status: status}} when status in 200..299 -> {:cont, :ok}
        {:ok, %{status: status}} -> {:halt, {:error, {:copy_failed, name, status}}}
        {:error, reason} -> {:halt, {:error, {:copy_failed, name, reason}}}
      end
    end)
  end

  defp rewrite_jsons(
         req,
         fetcher,
         base_url,
         bucket,
         src_prefix,
         dst_prefix,
         src_channel,
         dst_channel,
         names
       ) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      src_url = "#{base_url}/#{src_prefix}/#{src_channel}/#{name}"

      # Rewrite the full prefix/channel path first (covers every URL/remote_key),
      # then any bare prefix leftovers, so production references point at
      # dst_prefix/dst_channel.
      rewritten =
        fn body ->
          body
          |> to_string_body()
          |> String.replace("#{src_prefix}/#{src_channel}", "#{dst_prefix}/#{dst_channel}")
          |> String.replace(src_prefix, dst_prefix)
        end

      case fetcher.(src_url) do
        # Optional per-target fragments (manifest.d/*) are absent in older
        # single-file manifests — skip a source that does not exist.
        {:error, {:fetch_failed, _url, 404}} ->
          {:cont, :ok}

        {:ok, body} ->
          case Req.put(req,
                 url: "/#{bucket}/#{dst_prefix}/#{dst_channel}/#{name}",
                 body: rewritten.(body)
               ) do
            {:ok, %{status: status}} when status in 200..299 -> {:cont, :ok}
            error -> {:halt, {:error, {:rewrite_failed, name, error}}}
          end

        error ->
          {:halt, {:error, {:rewrite_failed, name, error}}}
      end
    end)
  end

  defp to_string_body(body) when is_binary(body), do: body
  defp to_string_body(body), do: Jason.encode!(body)

  defp default_promote_fetch(url) do
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:fetch_failed, url, status}}
      {:error, reason} -> {:error, {:fetch_failed, url, reason}}
    end
  end
end
