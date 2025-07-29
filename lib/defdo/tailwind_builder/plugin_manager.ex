defmodule Defdo.TailwindBuilder.PluginManager do
  @moduledoc """
  Specialized module for handling Tailwind CSS plugins.

  Responsibilities:
  - Apply plugin patches to configuration files
  - Validate plugin compatibility with versions
  - Handle different configuration formats (v3 vs v4)
  - Detect already installed plugins

  Does not handle download or compilation, only plugin integration.
  """

  require Logger
  alias Defdo.TailwindBuilder.Core

  @doc """
  Applies a plugin to Tailwind files
  """
  def apply_plugin(plugin_spec, opts \\ []) do
    opts = Keyword.validate!(opts, [
      :version,
      :base_path,
      :plugin_name,
      :validate_compatibility
    ])

    version = opts[:version] || raise ArgumentError, "version is required"
    base_path = opts[:base_path] || raise ArgumentError, "base_path is required"
    validate_compatibility = Keyword.get(opts, :validate_compatibility, true)

    with {:validate_spec, :ok} <- {:validate_spec, validate_plugin_spec(plugin_spec)},
         {:validate_compat, :ok} <- {:validate_compat, maybe_validate_compatibility(plugin_spec, version, validate_compatibility)},
         {:get_files, {:ok, files_to_patch}} <- {:get_files, get_files_to_patch(version)},
         {:apply_patches, {:ok, results}} <- {:apply_patches, apply_patches_to_files(plugin_spec, files_to_patch, version, base_path)} do

      result = %{
        plugin: extract_plugin_name(plugin_spec),
        version: version,
        files_patched: length(results),
        patch_results: results
      }

      {:ok, result}
    else
      {step, error} ->
        Logger.error("Plugin application failed at step #{step}: #{inspect(error)}")
        {:error, {step, error}}
    end
  end

  @doc """
  Checks if a plugin is already applied to the files
  """
  def plugin_already_applied?(plugin_spec, version, base_path) do
    case get_files_to_patch(version) do
      {:ok, files_to_patch} ->
        Enum.any?(files_to_patch, fn {relative_path, filename} ->
          file_path = build_file_path(base_path, version, filename, relative_path)

          if File.exists?(file_path) do
            content = File.read!(file_path)
            plugin_detected_in_content?(content, plugin_spec, filename)
          else
            false
          end
        end)

      {:error, _} -> false
    end
  end

  @doc """
  Gets information about plugin compatibility with a version
  """
  def get_plugin_compatibility(plugin_spec, version) do
    plugin_name = extract_plugin_name(plugin_spec)
    constraints = Core.get_version_constraints(version)

    %{
      plugin_name: plugin_name,
      version: version,
      major_version: constraints.major_version,
      dependency_section: constraints.plugin_system.dependency_section,
      requires_bundling: constraints.plugin_system.requires_bundling,
      supports_dynamic_import: constraints.plugin_system.supports_dynamic_import,
      config_files: constraints.file_structure.config_files,
      is_compatible: is_plugin_compatible?(plugin_spec, constraints)
    }
  end

  @doc """
  Validates the plugin specification format
  """
  def validate_plugin_spec(plugin_spec) when is_map(plugin_spec) do
    cond do
      not Map.has_key?(plugin_spec, "version") ->
        {:error, {:missing_required_key, "version"}}

      not String.contains?(plugin_spec["version"], ":") ->
        {:error, {:invalid_version_format, "version must contain package:version format"}}

      true ->
        :ok
    end
  end

  def validate_plugin_spec(plugin_name) when is_binary(plugin_name) do
    # Predefined plugin, assume valid
    :ok
  end

  def validate_plugin_spec(_), do: {:error, {:invalid_spec_type, "must be map or string"}}

  @doc """
  Extracts the plugin name from the specification
  """
  def extract_plugin_name(plugin_spec) when is_map(plugin_spec) do
    plugin_spec["version"]
    |> String.split(":", parts: 2)
    |> List.first()
    |> String.replace("\"", "")
  end

  def extract_plugin_name(plugin_name) when is_binary(plugin_name), do: plugin_name

  @doc """
  Applies a patch to a specific file according to its type
  """
  def patch_file_content(content, plugin_spec, filename, version) do
    case filename do
      "package.json" ->
        case patch_package_json(content, plugin_spec, version) do
          {:ok, new_content} -> {:ok, new_content}
          new_content when is_binary(new_content) -> {:ok, new_content}
          error -> error
        end

      "standalone.js" ->
        case patch_standalone_js(content, plugin_spec) do
          {:ok, new_content} -> {:ok, new_content}
          new_content when is_binary(new_content) -> {:ok, new_content}
          error -> error
        end

      "index.ts" ->
        case patch_index_ts(content, plugin_spec) do
          {:ok, new_content} -> {:ok, new_content}
          new_content when is_binary(new_content) -> {:ok, new_content}
          error -> error
        end

      _ -> {:error, {:unsupported_file_type, filename}}
    end
  end

  # Private functions

  defp maybe_validate_compatibility(plugin_spec, version, true) do
    if is_plugin_compatible?(plugin_spec, Core.get_version_constraints(version)) do
      :ok
    else
      {:error, :plugin_not_compatible}
    end
  end

  defp maybe_validate_compatibility(_plugin_spec, _version, false), do: :ok

  defp is_plugin_compatible?(_plugin_spec, constraints) do
    # For now, we assume all plugins are compatible
    # if the plugin system is available
    map_size(constraints.plugin_system) > 0
  end

  defp get_files_to_patch(version) do
    constraints = Core.get_version_constraints(version)

    case constraints.major_version do
      :v3 -> {:ok, [{"", "package.json"}, {"", "standalone.js"}]}
      :v4 -> {:ok, [{"", "package.json"}, {"src", "index.ts"}]}
      _ -> {:error, :unsupported_version}
    end
  end

  defp apply_patches_to_files(plugin_spec, files_to_patch, version, base_path) do
    plugin_name = extract_plugin_name(plugin_spec)

    results = for {relative_path, filename} <- files_to_patch do
      Logger.debug("Patching #{filename} with plugin #{plugin_name}")

      file_path = build_file_path(base_path, version, filename, relative_path)

      case read_and_patch_file(file_path, plugin_spec, filename, version) do
        {:ok, new_content} ->
          File.write!(file_path, new_content)
          "Patch to #{filename} was applied."

        {:skip, _reason} ->
          "Patch to #{filename} was applied."

        {:error, reason} ->
          {:error, reason}
      end
    end

    # Check if there were errors
    errors = Enum.filter(results, fn
      {:error, _} -> true
      _ -> false
    end)

    if Enum.empty?(errors) do
      {:ok, results}
    else
      {:error, {:patch_failures, errors}}
    end
  end

  defp read_and_patch_file(file_path, plugin_spec, filename, version) do
    if File.exists?(file_path) do
      content = File.read!(file_path)

      if plugin_detected_in_content?(content, plugin_spec, filename) do
        {:skip, "Plugin already applied to #{filename}"}
      else
        case patch_file_content(content, plugin_spec, filename, version) do
          {:ok, new_content} -> {:ok, new_content}
          new_content when is_binary(new_content) -> {:ok, new_content}
          error -> error
        end
      end
    else
      {:error, {:file_not_found, file_path}}
    end
  end

  defp plugin_detected_in_content?(content, plugin_spec, filename) do
    case filename do
      "package.json" ->
        plugin_version = plugin_spec["version"]
        content =~ plugin_version

      "standalone.js" ->
        statement = plugin_spec["statement"]
        statement && content =~ statement

      "index.ts" ->
        plugin_name = extract_plugin_name(plugin_spec)
        content =~ ~s|id === '#{plugin_name}'| ||
        content =~ ~s|id.startsWith('#{plugin_name}/')| ||
        content =~ ~s|'#{plugin_name}': await import('#{plugin_name}')|

      _ -> false
    end
  end

  defp build_file_path(base_path, version, filename, relative_path) do
    constraints = Core.get_version_constraints(version)

    project_base = case constraints.major_version do
      :v4 -> Path.join([base_path, "tailwindcss-#{version}", "packages", "@tailwindcss-standalone"])
      :v3 -> Path.join([base_path, "tailwindcss-#{version}", "standalone-cli"])
      _ -> base_path
    end

    Path.join([project_base, relative_path, filename])
  end

  # File type specific patching functions

  defp patch_package_json(content, plugin_spec, version) do
    plugin_version = plugin_spec["version"]

    if content =~ plugin_version do
      Logger.info("It's previously patched, we don't do it again")
      {:ok, content}
    else
      patch_package_json_with_json(content, plugin_version, version)
    end
  end

  defp patch_package_json_with_json(content, plugin_version, version) do
    try do
      package_json = Jason.decode!(content)

      constraints = Core.get_version_constraints(version)
      dep_section = constraints.plugin_system.dependency_section

      [plugin_name, plugin_ver] = String.split(plugin_version, ": ", parts: 2)
      plugin_name = String.trim(plugin_name, "\"")
      plugin_ver = String.trim(plugin_ver, "\"")

      package_json = Map.put_new(package_json, dep_section, %{})
      updated_deps = Map.put(package_json[dep_section], plugin_name, plugin_ver)
      updated_package_json = Map.put(package_json, dep_section, updated_deps)

      {:ok, Jason.encode!(updated_package_json, pretty: true)}
    rescue
      error ->
        Logger.warning("JSON parsing failed: #{inspect(error)}")
        Logger.warning("Falling back to string-based patching")

        # Fallback to original string-based patching
        patch_string_at =
          if Version.compare(version, "4.0.0") in [:eq, :gt] do
            """
            "dependencies": {
            """
          else
            """
            "devDependencies": {
            """
          end

        case split_with_self_plugin(content, patch_string_at) do
          {beginning, splitter, rest} ->
            order_parts = [beginning, splitter, "    ", plugin_version, ?,, ?\n, rest]
            new_content = IO.iodata_to_binary(order_parts)
            {:ok, new_content}

          _ ->
            {:error, :unable_to_patch}
        end
    end
  end

  defp patch_standalone_js(content, plugin_spec) do
    statement = plugin_spec["statement"]

    if statement == nil do
      {:error, {:missing_statement, "standalone.js requires statement in plugin spec"}}
    else
      if content =~ statement do
        Logger.info("It's previously patched, we don't patch it again")
        {:ok, content}
      else
        patch_string_at = """
        let localModules = {
        """

        case split_with_self_plugin(content, patch_string_at) do
          {beginning, splitter, rest} ->
            order_parts = [beginning, splitter, "  ", statement, ?,, ?\n, rest]
            new_content = IO.iodata_to_binary(order_parts)
            {:ok, new_content}

          _ ->
            {:error, :unable_to_patch}
        end
      end
    end
  end

  defp patch_index_ts(content, plugin_spec) do
    plugin_name = extract_plugin_name(plugin_spec)

    already_patched? =
      content =~ ~s|id === '#{plugin_name}'| ||
      content =~ ~s|id.startsWith('#{plugin_name}/')| ||
      content =~ ~s|'#{plugin_name}': await import('#{plugin_name}')|

    if already_patched? do
      Logger.info("Plugin #{plugin_name} already patched in index.ts, skipping")
      {:ok, content}
    else
      # Aplicar múltiples patches para index.ts
      patched_content = content
      |> patch_tw_resolve(plugin_name)
      |> patch_special_path(plugin_name)
      |> patch_tw_load(plugin_name)
      |> patch_bundled_imports(plugin_name)

      {:ok, patched_content}
    end
  end

  # Helper patching functions (reused from original code)

  defp patch_tw_resolve(content, plugin_name) do
    patch_string_at = """
    id.startsWith('@tailwindcss/') ||
    """

    patch_text = ~s[id.startsWith('#{plugin_name}') ||]

    case patch_content(content, patch_string_at, patch_text, "    ", false, :after) do
      {:ok, new_content} -> new_content
      _error -> content
    end
  end

  defp patch_special_path(content, plugin_name) do
    patch_string_at = ~s[  switch (id) {]

    patch_text = ~s[  if (/(\\/)?#{plugin_name}(\\/.+)?$/.test(id)) { return id }\n  ]

    case patch_content(content, patch_string_at, patch_text, "", false, :before) do
      {:ok, new_content} -> new_content
      _error -> content
    end
  end

  defp patch_tw_load(content, plugin_name) do
    patch_string_at = ~s[    return require('@tailwindcss/aspect-ratio')]

    patch_text = ~s[\n  } else if (/(\\/)?#{plugin_name}(\\/.+)?$/.test(id)) {\n    return require('#{plugin_name}')]

    case patch_content(content, patch_string_at, patch_text, "", false, :after) do
      {:ok, new_content} -> new_content
      _error -> content
    end
  end

  defp patch_bundled_imports(content, plugin_name) do
    patch_string_at = """
      'tailwindcss/defaultTheme.js': await import('tailwindcss/defaultTheme'),
    """

    patch_text = ~s[      '#{plugin_name}': await import('#{plugin_name}'),]

    case patch_content(content, patch_string_at, patch_text, "", false, :after) do
      {:ok, new_content} -> new_content
      _error -> content
    end
  end

  defp patch_content(content, string_to_split_on, patch_text, spacer, add_comma, insert_mode) do
    case split_with_self(content, string_to_split_on) do
      {beginning, splitter, rest} ->
        order_parts = if insert_mode == :before do
          if add_comma do
            [beginning, patch_text, ?,, ?\n, splitter, spacer, rest]
          else
            [beginning, patch_text, ?\n, splitter, spacer, rest]
          end
        else
          if add_comma do
            [beginning, splitter, spacer, patch_text, ?,, ?\n, rest]
          else
            [beginning, splitter, spacer, patch_text, ?\n, rest]
          end
        end

        new_content = IO.iodata_to_binary(order_parts)
        {:ok, new_content}

      _ ->
        {:error, :unable_to_patch}
    end
  end

  defp split_with_self(contents, text) do
    case :binary.split(contents, text) do
      [left, right] -> {left, text, right}
      [_] -> :error
    end
  end

  defp split_with_self_plugin(contents, text) do
    case :binary.split(contents, text) do
      [left, right] -> {left, text, right}
      [_] -> :error
    end
  end
end
