defmodule Defdo.TailwindBuilder.Core.Targets do
  @moduledoc """
  Target normalization helpers that bridge canonical product targets,
  legacy repository targets, toolchain build targets, and published
  artifact filenames.
  """

  # `tier` classifies a target for release promotion:
  #
  #   * `:required` — the release cannot be promoted to prod unless this target
  #     is published. These are the platforms defdo ships to production (k3s
  #     amd64 + arm64) and develops on (Apple Silicon).
  #   * `:optional` — nice-to-have coverage. A missing optional target is
  #     surfaced in the UI but never blocks promotion.
  #
  # `tailwind_official` marks targets tailwindlabs ships on GitHub (linux
  # x64/arm64/armv7, macOS x64/arm64, windows x64/arm64). The remaining targets
  # (freebsd, android) are defdo-builder extras with no upstream artifact.
  @target_definitions [
    %{
      target_key: "linux-x64",
      legacy_target: "linux-x64",
      build_target: "x86_64-unknown-linux-gnu",
      artifact_name: "tailwindcss-linux-x64",
      tier: :required,
      tailwind_official: true,
      aliases: ["linux-x64", "x86_64-unknown-linux-gnu", "x86_64-unknown-linux-musl"]
    },
    %{
      target_key: "linux-arm64",
      legacy_target: "linux-arm64",
      build_target: "aarch64-unknown-linux-gnu",
      artifact_name: "tailwindcss-linux-arm64",
      tier: :required,
      tailwind_official: true,
      aliases: ["linux-arm64", "aarch64-unknown-linux-gnu", "aarch64-unknown-linux-musl"]
    },
    %{
      target_key: "linux-arm",
      legacy_target: "linux-arm",
      build_target: "armv7-unknown-linux-gnueabihf",
      artifact_name: "tailwindcss-linux-arm",
      tier: :optional,
      tailwind_official: true,
      aliases: ["linux-arm", "armv7-unknown-linux-gnueabihf", "armv7-unknown-linux-musleabihf"]
    },
    %{
      target_key: "macos-x64",
      legacy_target: "darwin-x64",
      build_target: "x86_64-apple-darwin",
      artifact_name: "tailwindcss-macos-x64",
      tier: :optional,
      tailwind_official: true,
      aliases: ["macos-x64", "darwin-x64", "x86_64-apple-darwin"]
    },
    %{
      target_key: "macos-arm64",
      legacy_target: "darwin-arm64",
      build_target: "aarch64-apple-darwin",
      artifact_name: "tailwindcss-macos-arm64",
      tier: :required,
      tailwind_official: true,
      aliases: ["macos-arm64", "darwin-arm64", "aarch64-apple-darwin"]
    },
    %{
      target_key: "windows-x64",
      legacy_target: "win32-x64",
      build_target: "x86_64-pc-windows-msvc",
      artifact_name: "tailwindcss-windows-x64.exe",
      tier: :optional,
      tailwind_official: true,
      aliases: ["windows-x64", "win32-x64", "x86_64-pc-windows-msvc"]
    },
    %{
      target_key: "windows-arm64",
      legacy_target: "win32-arm64",
      build_target: "aarch64-pc-windows-msvc",
      artifact_name: "tailwindcss-windows-arm64.exe",
      tier: :optional,
      tailwind_official: true,
      aliases: ["windows-arm64", "win32-arm64", "aarch64-pc-windows-msvc"]
    },
    %{
      target_key: "freebsd-x64",
      legacy_target: "freebsd-x64",
      build_target: "x86_64-unknown-freebsd",
      artifact_name: "tailwindcss-freebsd-x64",
      tier: :optional,
      tailwind_official: false,
      aliases: ["freebsd-x64", "x86_64-unknown-freebsd"]
    },
    %{
      target_key: "android-arm64",
      legacy_target: "android-arm64",
      build_target: "aarch64-linux-android",
      artifact_name: "tailwindcss-android-arm64",
      tier: :optional,
      tailwind_official: false,
      aliases: ["android-arm64", "aarch64-linux-android"]
    },
    %{
      target_key: "android-arm",
      legacy_target: "android-arm",
      build_target: "armv7-linux-androideabi",
      artifact_name: "tailwindcss-android-arm",
      tier: :optional,
      tailwind_official: false,
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
           artifact_name: definition.artifact_name,
           tier: definition.tier,
           tailwind_official: definition.tailwind_official
         }}
    end
  end

  @doc """
  Return every canonical target key in definition order.
  """
  def all_target_keys, do: Enum.map(@target_definitions, & &1.target_key)

  @doc """
  Return the canonical target keys tailwindlabs ships on GitHub (linux
  x64/arm64/armv7, macOS x64/arm64, windows x64/arm64), in definition order.
  """
  def tailwind_target_keys do
    for d <- @target_definitions, d.tailwind_official, do: d.target_key
  end

  @doc """
  Return the target keys that must be published before a release can be
  promoted to prod (`:required` tier), in definition order.
  """
  def required_target_keys do
    for d <- @target_definitions, d.tier == :required, do: d.target_key
  end

  @doc """
  Return the `:optional` tier target keys, in definition order.
  """
  def optional_target_keys do
    for d <- @target_definitions, d.tier == :optional, do: d.target_key
  end

  @doc """
  Return the promotion tier (`:required` | `:optional`) for a target, or
  `nil` when the target is unknown.
  """
  def tier(target) do
    case normalize(target) do
      {:ok, normalized} -> normalized.tier
      _ -> nil
    end
  end

  @doc """
  Return true when the target must be published for prod promotion.
  """
  def required?(target), do: tier(target) == :required

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

  @filename_target_rules [
    {["darwin", "macos", "apple"], ["arm64", "aarch64"], false, "macos-arm64"},
    {["darwin", "macos", "apple"], ["x86_64", "x64"], false, "macos-x64"},
    {["windows", "win32"], ["arm64", "aarch64"], false, "windows-arm64"},
    {["windows", "win32"], ["x86_64", "x64"], false, "windows-x64"},
    {["linux"], ["arm64", "aarch64"], true, "linux-arm64-musl"},
    {["linux"], ["arm64", "aarch64"], false, "linux-arm64"},
    {["linux"], ["armv7", "arm"], true, "linux-arm-musl"},
    {["linux"], ["armv7", "arm"], false, "linux-arm"},
    {["linux"], ["x86_64", "x64"], true, "linux-x64-musl"},
    {["linux"], ["x86_64", "x64"], false, "linux-x64"},
    {:freebsd, "freebsd-x64"},
    {["android"], ["arm64", "aarch64"], false, "android-arm64"},
    {["android"], ["armv7", "arm"], false, "android-arm"}
  ]

  @doc """
  Infer a canonical target key from a published binary filename.
  """
  def target_key_from_filename(filename) when is_binary(filename) do
    normalized = String.downcase(filename)

    Enum.find_value(@filename_target_rules, fn
      {:freebsd, key} ->
        if String.contains?(normalized, "freebsd"), do: key

      {os_tokens, arch_tokens, musl?, key} ->
        if filename_rule_matches?(normalized, os_tokens, arch_tokens, musl?), do: key
    end)
  end

  defp filename_rule_matches?(normalized, os_tokens, arch_tokens, musl?) do
    contains_os_arch?(normalized, os_tokens, arch_tokens) and
      (not musl? or String.contains?(normalized, "musl"))
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
