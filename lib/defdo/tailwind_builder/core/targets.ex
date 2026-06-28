defmodule Defdo.TailwindBuilder.Core.Targets do
  @moduledoc """
  Target normalization helpers that bridge canonical product targets,
  legacy repository targets, toolchain build targets, and published
  artifact filenames.
  """

  @target_definitions [
    %{
      target_key: "linux-x64",
      legacy_target: "linux-x64",
      build_target: "x86_64-unknown-linux-gnu",
      artifact_name: "tailwindcss-linux-x64",
      aliases: ["linux-x64", "x86_64-unknown-linux-gnu", "x86_64-unknown-linux-musl"]
    },
    %{
      target_key: "linux-arm64",
      legacy_target: "linux-arm64",
      build_target: "aarch64-unknown-linux-gnu",
      artifact_name: "tailwindcss-linux-arm64",
      aliases: ["linux-arm64", "aarch64-unknown-linux-gnu", "aarch64-unknown-linux-musl"]
    },
    %{
      target_key: "linux-arm",
      legacy_target: "linux-arm",
      build_target: "armv7-unknown-linux-gnueabihf",
      artifact_name: "tailwindcss-linux-arm",
      aliases: ["linux-arm", "armv7-unknown-linux-gnueabihf", "armv7-unknown-linux-musleabihf"]
    },
    %{
      target_key: "macos-x64",
      legacy_target: "darwin-x64",
      build_target: "x86_64-apple-darwin",
      artifact_name: "tailwindcss-macos-x64",
      aliases: ["macos-x64", "darwin-x64", "x86_64-apple-darwin"]
    },
    %{
      target_key: "macos-arm64",
      legacy_target: "darwin-arm64",
      build_target: "aarch64-apple-darwin",
      artifact_name: "tailwindcss-macos-arm64",
      aliases: ["macos-arm64", "darwin-arm64", "aarch64-apple-darwin"]
    },
    %{
      target_key: "windows-x64",
      legacy_target: "win32-x64",
      build_target: "x86_64-pc-windows-msvc",
      artifact_name: "tailwindcss-windows-x64.exe",
      aliases: ["windows-x64", "win32-x64", "x86_64-pc-windows-msvc"]
    },
    %{
      target_key: "windows-arm64",
      legacy_target: "win32-arm64",
      build_target: "aarch64-pc-windows-msvc",
      artifact_name: "tailwindcss-windows-arm64.exe",
      aliases: ["windows-arm64", "win32-arm64", "aarch64-pc-windows-msvc"]
    },
    %{
      target_key: "freebsd-x64",
      legacy_target: "freebsd-x64",
      build_target: "x86_64-unknown-freebsd",
      artifact_name: "tailwindcss-freebsd-x64",
      aliases: ["freebsd-x64", "x86_64-unknown-freebsd"]
    },
    %{
      target_key: "android-arm64",
      legacy_target: "android-arm64",
      build_target: "aarch64-linux-android",
      artifact_name: "tailwindcss-android-arm64",
      aliases: ["android-arm64", "aarch64-linux-android"]
    },
    %{
      target_key: "android-arm",
      legacy_target: "android-arm",
      build_target: "armv7-linux-androideabi",
      artifact_name: "tailwindcss-android-arm",
      aliases: ["android-arm", "armv7-linux-androideabi"]
    }
  ]

  @definitions_by_alias Enum.reduce(@target_definitions, %{}, fn definition, acc ->
                          Enum.reduce(definition.aliases, acc, fn alias_name, inner_acc ->
                            Map.put(inner_acc, alias_name, definition)
                          end)
                        end)

  @doc """
  Normalize a target into canonical target metadata.
  """
  def normalize(target) when is_atom(target), do: normalize(Atom.to_string(target))

  def normalize(target) when is_binary(target) do
    normalized_target = String.downcase(target)

    case Map.get(@definitions_by_alias, normalized_target) do
      nil ->
        {:error, :unknown_target}

      definition ->
        {:ok,
         %{
           input: target,
           target_key: definition.target_key,
           legacy_target: definition.legacy_target,
           build_target: definition.build_target,
           artifact_name: definition.artifact_name
         }}
    end
  end

  @doc """
  Return the canonical product-facing target key.
  """
  def canonical_target_key(target) do
    with {:ok, normalized} <- normalize(target) do
      normalized.target_key
    end
  end

  @doc """
  Return the legacy repository target alias.
  """
  def legacy_target(target) do
    with {:ok, normalized} <- normalize(target) do
      normalized.legacy_target
    end
  end

  @doc """
  Return the preferred build target for a canonical or legacy target.
  """
  def build_target(target) do
    with {:ok, normalized} <- normalize(target) do
      normalized.build_target
    end
  end

  @doc """
  Return the published artifact filename for a target.
  """
  def artifact_name(target) do
    with {:ok, normalized} <- normalize(target) do
      normalized.artifact_name
    end
  end

  @doc """
  Return true when two target identifiers refer to the same logical platform.
  """
  def matches?(left, right) do
    not MapSet.disjoint?(match_tokens(left), match_tokens(right))
  end

  @doc """
  Infer a canonical target key from a published binary filename.
  """
  def target_key_from_filename(filename) when is_binary(filename) do
    normalized = String.downcase(filename)

    cond do
      contains_os_arch?(normalized, ["darwin", "macos", "apple"], ["arm64", "aarch64"]) ->
        "macos-arm64"

      contains_os_arch?(normalized, ["darwin", "macos", "apple"], ["x86_64", "x64"]) ->
        "macos-x64"

      contains_os_arch?(normalized, ["windows", "win32"], ["arm64", "aarch64"]) ->
        "windows-arm64"

      contains_os_arch?(normalized, ["windows", "win32"], ["x86_64", "x64"]) ->
        "windows-x64"

      contains_os_arch?(normalized, ["linux"], ["arm64", "aarch64"]) and
          String.contains?(normalized, "musl") ->
        "linux-arm64-musl"

      contains_os_arch?(normalized, ["linux"], ["arm64", "aarch64"]) ->
        "linux-arm64"

      contains_os_arch?(normalized, ["linux"], ["armv7", "arm"]) and
          String.contains?(normalized, "musl") ->
        "linux-arm-musl"

      contains_os_arch?(normalized, ["linux"], ["armv7", "arm"]) ->
        "linux-arm"

      contains_os_arch?(normalized, ["linux"], ["x86_64", "x64"]) and
          String.contains?(normalized, "musl") ->
        "linux-x64-musl"

      contains_os_arch?(normalized, ["linux"], ["x86_64", "x64"]) ->
        "linux-x64"

      String.contains?(normalized, "freebsd") ->
        "freebsd-x64"

      contains_os_arch?(normalized, ["android"], ["arm64", "aarch64"]) ->
        "android-arm64"

      contains_os_arch?(normalized, ["android"], ["armv7", "arm"]) ->
        "android-arm"

      true ->
        nil
    end
  end

  defp match_tokens(target) when is_atom(target), do: match_tokens(Atom.to_string(target))

  defp match_tokens(target) when is_binary(target) do
    case normalize(target) do
      {:ok, normalized} ->
        MapSet.new([
          normalized.target_key,
          normalized.legacy_target,
          normalized.build_target
        ])

      {:error, :unknown_target} ->
        MapSet.new([String.downcase(target)])
    end
  end

  defp contains_os_arch?(value, os_patterns, arch_patterns) do
    contains_any?(value, os_patterns) and contains_any?(value, arch_patterns)
  end

  defp contains_any?(value, patterns) do
    Enum.any?(patterns, &String.contains?(value, &1))
  end
end
