defmodule Defdo.TailwindBuilder.ManifestManager do
  @moduledoc """
  Post-build manifest manager for Tailwind artifacts.

  Maintains two independent manifests:
  - `build-manifest.json` for compiler-internal state
  - `release-manifest.json` for consumer-facing availability

  The manager performs target-canonicalized, idempotent upserts under a
  distributed lock and only rewrites files through atomic temp-file renames.
  """

  require Logger

  alias Defdo.TailwindBuilder.Core

  @build_manifest_filename "build-manifest.json"
  @release_manifest_filename "release-manifest.json"

  @doc """
  Canonicalize a target identifier into the manifest key format.

  Accepts Rust triples, architecture shortcuts, and artifact filename hints.
  """
  def canonical_target(target) when is_atom(target),
    do: target |> Atom.to_string() |> canonical_target()

  def canonical_target(target) when is_binary(target) do
    normalized =
      target
      |> String.trim()
      |> String.downcase()

    cond do
      normalized in ["macos-arm64", "darwin-arm64", "aarch64-apple-darwin"] ->
        "macos-arm64"

      normalized in ["macos-x64", "darwin-x64", "x86_64-apple-darwin"] ->
        "macos-x64"

      normalized in ["linux-musl-x64", "x86_64-unknown-linux-musl"] ->
        "linux-musl-x64"

      normalized in ["linux-musl-arm64", "aarch64-unknown-linux-musl"] ->
        "linux-musl-arm64"

      normalized in ["linux-x64", "x86_64-unknown-linux-gnu", "x86_64-linux-gnu"] ->
        "linux-x64"

      normalized in ["linux-arm64", "aarch64-unknown-linux-gnu", "aarch64-linux-gnu"] ->
        "linux-arm64"

      normalized in ["linux-armv7", "armv7-unknown-linux-gnueabihf"] ->
        "linux-armv7"

      normalized in ["linux-musl-armv7", "armv7-unknown-linux-musleabihf"] ->
        "linux-musl-armv7"

      normalized in ["win32-x64", "windows-x64", "x86_64-pc-windows-msvc"] ->
        "win32-x64"

      normalized in ["win32-arm64", "windows-arm64", "aarch64-pc-windows-msvc"] ->
        "win32-arm64"

      normalized in ["freebsd-x64", "x86_64-unknown-freebsd"] ->
        "freebsd-x64"

      normalized in ["freebsd-arm64", "aarch64-unknown-freebsd"] ->
        "freebsd-arm64"

      normalized in ["android-arm64", "aarch64-linux-android"] ->
        "android-arm64"

      normalized in ["android-armv7", "armv7-linux-androideabi"] ->
        "android-armv7"

      normalized in ["wasm32", "wasm32-unknown-unknown"] ->
        "wasm32"

      true ->
        normalized
        |> String.replace(~r/[^a-z0-9]+/, "-")
        |> String.trim("-")
    end
  end

  @doc """
  Upsert build and release manifests after a successful target build.
  """
  def upsert_post_build(opts) when is_list(opts) do
    opts =
      Keyword.validate!(opts, [
        :version,
        :source_path,
        :standalone_root,
        :target,
        :target_arch,
        :flavor,
        :expected_targets,
        :nodes,
        :workers,
        :manifest_dir,
        :build_manifest_path,
        :release_manifest_path
      ])

    version = Keyword.fetch!(opts, :version)
    source_path = Keyword.fetch!(opts, :source_path)
    flavor = Keyword.get(opts, :flavor, "standalone")
    build_target = resolve_build_target(opts)
    manifest_target = canonical_target(build_target || Core.get_host_architecture())

    standalone_root =
      Keyword.get(opts, :standalone_root, infer_standalone_root(source_path, version))

    manifest_dir = Keyword.get(opts, :manifest_dir, Path.join(standalone_root, "dist"))

    build_manifest_path =
      Keyword.get(opts, :build_manifest_path, Path.join(manifest_dir, @build_manifest_filename))

    release_manifest_path =
      Keyword.get(
        opts,
        :release_manifest_path,
        Path.join(manifest_dir, @release_manifest_filename)
      )

    expected_targets =
      normalize_targets(Keyword.get(opts, :expected_targets, default_expected_targets(version)))

    nodes = merge_lists(Keyword.get(opts, :nodes, []), Keyword.get(opts, :workers, []))

    case locate_artifact(standalone_root, manifest_target) do
      {:ok, artifact} ->
        case hash_artifact(artifact.path) do
          {:ok, artifact_hash} ->
            now = DateTime.utc_now() |> DateTime.to_iso8601()

            context = %{
              version: version,
              flavor: flavor,
              build_target: manifest_target,
              artifact: artifact,
              hash: artifact_hash,
              expected_targets: expected_targets,
              nodes: nodes,
              now: now,
              compilation_method: Core.get_compilation_method(version),
              build_manifest_path: build_manifest_path,
              release_manifest_path: release_manifest_path
            }

            lock_path = manifest_lock_path(build_manifest_path, release_manifest_path)

            with_manifest_lock(lock_path, fn -> patch_manifests(context) end)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def upsert_post_build(_opts), do: {:error, :invalid_manifest_options}

  defp patch_manifests(context) do
    with {:ok, existing_build} <- read_manifest(context.build_manifest_path),
         {:ok, existing_release} <- read_manifest(context.release_manifest_path),
         {:ok, build_manifest, build_changed?} <-
           merge_build_manifest(existing_build, context),
         {:ok, release_manifest, release_changed?} <-
           merge_release_manifest(existing_release, context) do
      build_write_result =
        if build_changed? do
          write_manifest_atomic(context.build_manifest_path, build_manifest)
        else
          {:ok, :unchanged}
        end

      case build_write_result do
        {:ok, _} ->
          release_write_result =
            if release_changed? do
              write_manifest_atomic(context.release_manifest_path, release_manifest)
            else
              {:ok, :unchanged}
            end

          case release_write_result do
            {:ok, _} ->
              {:ok,
               %{
                 status: if(build_changed? or release_changed?, do: :updated, else: :unchanged),
                 target: context.build_target,
                 build_manifest_path: context.build_manifest_path,
                 release_manifest_path: context.release_manifest_path,
                 build_manifest: build_manifest,
                 release_manifest: release_manifest
               }}

            {:error, reason} ->
              Logger.error("Failed writing release manifest: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Failed writing build manifest: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp merge_build_manifest(existing_manifest, context) do
    existing_manifest = normalize_manifest(existing_manifest)
    existing_version = Map.get(existing_manifest, "version")
    existing_flavor = Map.get(existing_manifest, "flavor")

    existing_expected_targets =
      normalize_targets(Map.get(existing_manifest, "expected_targets", []))

    current_expected_targets = normalize_targets(context.expected_targets)

    with :ok <- ensure_field_consistency(:version, existing_version, context.version),
         :ok <- ensure_field_consistency(:flavor, existing_flavor, context.flavor),
         :ok <-
           ensure_expected_targets_consistency(
             existing_expected_targets,
             current_expected_targets
           ) do
      targets = ensure_map(Map.get(existing_manifest, "targets", %{}))
      current_entry = build_target_entry(context)
      current_hash = current_entry["hash"]

      case Map.get(targets, context.build_target) do
        %{"hash" => existing_hash} when existing_hash == current_hash ->
          {:ok, existing_manifest, false}

        _ ->
          merged_targets = Map.put(targets, context.build_target, current_entry)
          available_targets = Map.keys(merged_targets) |> Enum.sort()

          expected_targets =
            if(existing_expected_targets == [],
              do: current_expected_targets,
              else: existing_expected_targets
            )

          missing_targets = expected_targets -- available_targets
          build_status = build_status(available_targets, missing_targets)

          split_hint =
            build_split_hint(context, available_targets, missing_targets, expected_targets)

          nodes = merge_lists(Map.get(existing_manifest, "nodes", []), context.nodes)
          workers = merge_lists(Map.get(existing_manifest, "workers", []), context.nodes)

          updated_manifest =
            existing_manifest
            |> Map.put("version", context.version)
            |> Map.put("flavor", context.flavor)
            |> Map.put("build_status", build_status)
            |> Map.put("expected_targets", expected_targets)
            |> Map.put("available_targets", available_targets)
            |> Map.put("missing_targets", missing_targets)
            |> Map.put("split_hint", split_hint)
            |> Map.put("nodes", nodes)
            |> Map.put("workers", workers)
            |> Map.put("targets", merged_targets)
            |> Map.put("updated_at", context.now)

          {:ok, updated_manifest, true}
      end
    end
  end

  defp merge_release_manifest(existing_manifest, context) do
    existing_manifest = normalize_manifest(existing_manifest)
    existing_version = Map.get(existing_manifest, "version")
    existing_flavor = Map.get(existing_manifest, "flavor")
    metadata = ensure_map(Map.get(existing_manifest, "metadata", %{}))

    existing_expected_targets =
      metadata
      |> Map.get("expected_targets", [])
      |> normalize_targets()

    current_expected_targets = normalize_targets(context.expected_targets)

    with :ok <- ensure_field_consistency(:version, existing_version, context.version),
         :ok <- ensure_field_consistency(:flavor, existing_flavor, context.flavor),
         :ok <-
           ensure_expected_targets_consistency(
             existing_expected_targets,
             current_expected_targets
           ) do
      hashes = ensure_map(Map.get(existing_manifest, "hash", %{}))
      current_hash = context.hash

      case Map.get(hashes, context.build_target) do
        hash when hash == current_hash ->
          {:ok, existing_manifest, false}

        _ ->
          merged_hashes = Map.put(hashes, context.build_target, current_hash)
          available_targets = Map.keys(merged_hashes) |> Enum.sort()

          expected_targets =
            if(existing_expected_targets == [],
              do: current_expected_targets,
              else: existing_expected_targets
            )

          missing_targets = expected_targets -- available_targets
          release_status = build_status(available_targets, missing_targets)

          split_hint =
            build_split_hint(context, available_targets, missing_targets, expected_targets)

          metadata_targets = ensure_map(Map.get(metadata, "targets", %{}))

          release_target_metadata =
            %{
              "artifact" => %{
                "filename" => context.artifact.filename,
                "relative_path" => context.artifact.relative_path,
                "size_bytes" => context.artifact.size_bytes
              },
              "status" => "published",
              "target" => context.build_target
            }

          updated_metadata =
            metadata
            |> Map.put("compilation_method", context.compilation_method)
            |> Map.put("build_status", release_status)
            |> Map.put("expected_targets", expected_targets)
            |> Map.put("available_targets", available_targets)
            |> Map.put("missing_targets", missing_targets)
            |> Map.put("split_hint", split_hint)
            |> Map.put(
              "targets",
              Map.put(metadata_targets, context.build_target, release_target_metadata)
            )

          updated_manifest =
            existing_manifest
            |> Map.put("version", context.version)
            |> Map.put("flavor", context.flavor)
            |> Map.put("status", release_status)
            |> Map.put("includes", available_targets)
            |> Map.put("published_at", context.now)
            |> Map.put("hash", merged_hashes)
            |> Map.put("metadata", updated_metadata)

          {:ok, updated_manifest, true}
      end
    end
  end

  defp build_target_entry(context) do
    %{
      "artifact" => %{
        "filename" => context.artifact.filename,
        "relative_path" => context.artifact.relative_path,
        "size_bytes" => context.artifact.size_bytes,
        "modified_at" => context.artifact.modified_at,
        "target_hint" => context.artifact.target_hint
      },
      "hash" => context.hash,
      "status" => "built",
      "target" => context.build_target,
      "updated_at" => context.now
    }
  end

  defp build_split_hint(context, available_targets, missing_targets, expected_targets) do
    %{
      "mode" => if(length(expected_targets) > 1, do: "fan_out", else: "single_target"),
      "strategy" => "per_target",
      "target" => context.build_target,
      "available_targets" => available_targets,
      "missing_targets" => missing_targets,
      "expected_targets" => expected_targets
    }
  end

  defp build_status(available_targets, missing_targets) do
    if available_targets != [] and missing_targets == [] do
      "complete"
    else
      "partial"
    end
  end

  defp ensure_expected_targets_consistency([], _current), do: :ok
  defp ensure_expected_targets_consistency(_existing, []), do: :ok
  defp ensure_expected_targets_consistency(existing, current) when existing == current, do: :ok

  defp ensure_expected_targets_consistency(existing, current) do
    {:error, {:expected_targets_mismatch, %{existing: existing, incoming: current}}}
  end

  defp ensure_field_consistency(_field, nil, _current), do: :ok
  defp ensure_field_consistency(_field, current, current), do: :ok

  defp ensure_field_consistency(field, existing, current) do
    {:error, {:"#{field}_mismatch", %{existing: existing, incoming: current}}}
  end

  defp resolve_build_target(opts) do
    target = Keyword.get(opts, :target)
    target_arch = Keyword.get(opts, :target_arch)
    version = Keyword.fetch!(opts, :version)

    cond do
      not is_nil(target) ->
        target

      is_binary(target_arch) and Core.can_compile_for_target?(version, target_arch) ->
        target_arch

      is_atom(target_arch) and Core.can_compile_for_target?(version, Atom.to_string(target_arch)) ->
        Atom.to_string(target_arch)

      true ->
        nil
    end
  end

  defp normalize_targets(targets) when is_list(targets) do
    targets
    |> Enum.map(&canonical_target/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_targets(_), do: []

  defp normalize_jsonish_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_jsonish/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_jsonish_list(_), do: []

  defp normalize_jsonish(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), normalize_jsonish(nested)} end)
    |> Enum.into(%{})
  end

  defp normalize_jsonish(value) when is_list(value), do: Enum.map(value, &normalize_jsonish/1)
  defp normalize_jsonish(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_jsonish(value), do: value

  defp merge_lists(existing, incoming) do
    (normalize_jsonish_list(existing) ++ normalize_jsonish_list(incoming))
    |> Enum.uniq()
  end

  defp normalize_manifest(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), normalize_jsonish(nested)} end)
    |> Enum.into(%{})
  end

  defp normalize_manifest(_), do: %{}

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_), do: %{}

  defp infer_standalone_root(source_path, version) do
    tailwind_root = Path.join(source_path, "tailwindcss-#{version}")

    case Core.get_version_constraints(version).major_version do
      :v3 -> Path.join(tailwind_root, "standalone-cli")
      _ -> Path.join([tailwind_root, "packages", "@tailwindcss-standalone"])
    end
  end

  defp default_expected_targets(version) do
    Core.get_supported_architectures(version)
    |> Enum.map(&canonical_target/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp locate_artifact(standalone_root, target) do
    dist_dir = Path.join(standalone_root, "dist")

    if File.exists?(dist_dir) do
      candidates =
        dist_dir
        |> Path.join("tailwindcss*")
        |> Path.wildcard()
        |> Enum.flat_map(&artifact_candidate(&1, standalone_root))

      case select_artifact_candidate(candidates, target) do
        nil -> {:error, {:artifact_not_found, target, dist_dir}}
        artifact -> {:ok, artifact}
      end
    else
      {:error, {:dist_directory_not_found, dist_dir}}
    end
  end

  defp artifact_candidate(path, standalone_root) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size, mtime: mtime}} ->
        basename = Path.basename(path)
        rooted = Path.rootname(basename)
        target_hint = canonical_target(String.replace_prefix(rooted, "tailwindcss-", ""))

        if artifact_file?(basename) do
          [
            %{
              path: path,
              filename: basename,
              relative_path: Path.relative_to(path, standalone_root),
              size_bytes: size,
              modified_at: inspect(mtime),
              target_hint: target_hint
            }
          ]
        else
          []
        end

      _ ->
        []
    end
  end

  defp artifact_file?(basename) do
    not String.ends_with?(basename, [".json", ".sha256", ".md5", ".txt", ".log"])
  end

  defp select_artifact_candidate([], _target), do: nil

  defp select_artifact_candidate(candidates, target) do
    exact_matches = Enum.filter(candidates, fn candidate -> candidate.target_hint == target end)

    case exact_matches do
      [single] ->
        single

      matches when matches != [] ->
        Enum.max_by(matches, &{&1.size_bytes, &1.filename})

      [] ->
        case candidates do
          [single] ->
            single

          many ->
            Enum.max_by(many, &{&1.size_bytes, &1.filename})
        end
    end
  end

  defp hash_artifact(path) do
    chunk_size = 64_000
    sha_ctx = :crypto.hash_init(:sha256)
    md5_ctx = :crypto.hash_init(:md5)

    try do
      {sha_ctx, md5_ctx} =
        File.stream!(path, [:binary], chunk_size)
        |> Enum.reduce({sha_ctx, md5_ctx}, fn chunk, {sha, md5} ->
          {:crypto.hash_update(sha, chunk), :crypto.hash_update(md5, chunk)}
        end)

      {:ok,
       %{
         "sha256" => Base.encode16(:crypto.hash_final(sha_ctx), case: :lower),
         "md5" => Base.encode16(:crypto.hash_final(md5_ctx), case: :lower)
       }}
    rescue
      error ->
        {:error, {:artifact_hash_failed, path, error}}
    end
  end

  defp read_manifest(path) do
    case File.read(path) do
      {:ok, content} ->
        content = String.trim(content)

        cond do
          content == "" ->
            {:ok, %{}}

          true ->
            case Jason.decode(content) do
              {:ok, manifest} -> {:ok, manifest}
              {:error, reason} -> {:error, {:invalid_manifest, path, reason}}
            end
        end

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, {:manifest_read_failed, path, reason}}
    end
  end

  defp write_manifest_atomic(path, manifest) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    tmp_path =
      path <>
        ".#{System.unique_integer([:positive, :monotonic])}.tmp"

    try do
      json = Jason.encode!(manifest, pretty: true)
      File.write!(tmp_path, json)

      case File.rename(tmp_path, path) do
        :ok ->
          {:ok, path}

        {:error, reason} ->
          File.rm(tmp_path)
          {:error, {:manifest_rename_failed, path, reason}}
      end
    rescue
      error ->
        File.rm(tmp_path)
        {:error, {:manifest_write_failed, path, error}}
    end
  end

  defp with_manifest_lock(lock_path, fun) when is_function(fun, 0) do
    acquire_manifest_lock(lock_path, fun, 0)
  end

  defp acquire_manifest_lock(lock_path, fun, attempts) do
    case File.open(lock_path, [:write, :exclusive]) do
      {:ok, io} ->
        try do
          IO.write(io, "#{inspect(self())}\n#{System.os_time(:millisecond)}")
          fun.()
        after
          File.close(io)
          File.rm(lock_path)
        end

      {:error, :eexist} ->
        if stale_lock?(lock_path) do
          File.rm(lock_path)
          acquire_manifest_lock(lock_path, fun, attempts + 1)
        else
          if attempts >= 3_000 do
            {:error, {:manifest_lock_timeout, lock_path}}
          else
            Process.sleep(10)
            acquire_manifest_lock(lock_path, fun, attempts + 1)
          end
        end

      {:error, reason} ->
        {:error, {:manifest_lock_failed, lock_path, reason}}
    end
  end

  defp stale_lock?(lock_path) do
    case File.stat(lock_path) do
      {:ok, %{mtime: mtime}} ->
        now = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time())
        lock_seconds = lock_mtime_seconds(mtime)

        now - lock_seconds > 86_400

      _ ->
        false
    end
  end

  defp lock_mtime_seconds({date, time}),
    do: :calendar.datetime_to_gregorian_seconds({date, time})

  defp manifest_lock_path(build_manifest_path, release_manifest_path) do
    digest =
      :erlang.phash2({Path.expand(build_manifest_path), Path.expand(release_manifest_path)})

    Path.join(System.tmp_dir!(), "tailwind_builder_manifest_#{digest}.lock")
  end
end
