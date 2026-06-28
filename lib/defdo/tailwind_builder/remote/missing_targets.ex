defmodule Defdo.TailwindBuilder.Remote.MissingTargets do
  @moduledoc """
  Pure helper that compares desired targets against discovered and published state.

  Returns a structured map with four buckets:

  - `:published` — targets that appear in the published manifest/metadata.
  - `:buildable_now` — targets discovered as build-capable on available hosts
    but not yet published.
  - `:missing` — targets that are desired but neither published nor buildable.
  - `:failed` — targets that were attempted but reported a build failure.

  All functions are pure; no I/O. Results are deterministic given the same inputs.

  ## Usage

      report = MissingTargets.report(
        desired: ["linux-x64", "linux-arm64", "macos-arm64"],
        buildable: ["linux-x64"],
        published: ["macos-arm64"],
        failed: []
      )
      # %{published: ["macos-arm64"], buildable_now: ["linux-x64"],
      #   missing: ["linux-arm64"], failed: []}
  """

  alias Defdo.TailwindBuilder.Core.Targets

  @doc """
  Compute the missing-targets report.

  Accepts keyword list or map:
  - `:desired` — list of target strings (any alias accepted by `Targets.normalize/1`).
  - `:published` — list of canonical target_keys already published.
  - `:buildable` — list of canonical target_keys that have a capable builder available.
  - `:failed` — list of canonical target_keys that failed during the current run.

  All target strings are normalised to canonical `target_key` form. Unknown
  aliases are kept as-is (so they always land in `:missing`).
  """
  @spec report(keyword() | map()) :: %{
          published: [String.t()],
          buildable_now: [String.t()],
          missing: [String.t()],
          failed: [String.t()]
        }
  def report(opts) when is_list(opts) do
    opts |> Enum.into(%{}) |> report()
  end

  def report(opts) when is_map(opts) do
    desired = normalize_list(Map.get(opts, :desired, []))
    published = normalize_list(Map.get(opts, :published, []))
    buildable = normalize_list(Map.get(opts, :buildable, []))
    failed = normalize_list(Map.get(opts, :failed, []))

    published_set = MapSet.new(published)
    buildable_set = MapSet.new(buildable)
    failed_set = MapSet.new(failed)

    desired_set = MapSet.new(desired)

    published_desired =
      MapSet.intersection(desired_set, published_set) |> MapSet.to_list() |> Enum.sort()

    buildable_now =
      desired_set
      |> MapSet.difference(published_set)
      |> MapSet.intersection(buildable_set)
      |> MapSet.to_list()
      |> Enum.sort()

    failed_desired =
      desired_set
      |> MapSet.difference(published_set)
      |> MapSet.intersection(failed_set)
      |> MapSet.to_list()
      |> Enum.sort()

    missing =
      desired_set
      |> MapSet.difference(published_set)
      |> MapSet.difference(buildable_set)
      |> MapSet.difference(failed_set)
      |> MapSet.to_list()
      |> Enum.sort()

    %{
      published: published_desired,
      buildable_now: buildable_now,
      missing: missing,
      failed: failed_desired
    }
  end

  @doc """
  Extract published `target_key` values from a decoded manifest map.

  Accepts the validated manifest map (with `:artifacts` key populated by
  `TailwindCompiler.Manifest.Client.validate/1` or equivalent).
  Also accepts raw manifest with `"files"` key.
  """
  @spec published_from_manifest(map()) :: [String.t()]
  def published_from_manifest(manifest) when is_map(manifest) do
    artifacts =
      Map.get(manifest, :artifacts) ||
        Map.get(manifest, "artifacts") ||
        Map.get(manifest, "files") ||
        []

    Enum.map(artifacts, fn artifact ->
      Map.get(artifact, :target_key) ||
        Map.get(artifact, "target_key") ||
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  Return all canonical target keys defined in `Defdo.TailwindBuilder.Core.Targets`.
  """
  @spec all_canonical_targets() :: [String.t()]
  def all_canonical_targets do
    ~w(
      linux-x64 linux-arm64 linux-arm
      macos-x64 macos-arm64
      windows-x64 windows-arm64
      freebsd-x64
      android-arm64 android-arm
    )
  end

  defp normalize_list(list) when is_list(list) do
    Enum.map(list, &normalize_target/1)
  end

  defp normalize_target(target) when is_binary(target) do
    case Targets.normalize(target) do
      {:ok, %{target_key: key}} -> key
      {:error, :unknown_target} -> target
    end
  end

  defp normalize_target(target), do: to_string(target)
end
