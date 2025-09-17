defmodule Defdo.TailwindBuilder do
  @moduledoc """
  Migrated version of TailwindBuilder that uses the new modular architecture.

  Maintains exactly the same public API as the original TailwindBuilder
  but internally uses the new specialized modules:
  - Downloader for download operations
  - PluginManager for plugin handling
  - Builder for compilation
  - Deployer for distribution
  - VersionFetcher for version information
  - ConfigProvider for business policies

  This migration demonstrates how the new modular architecture can
  integrate transparently with existing code.
  """

  require Logger

  # Import all modules from the new architecture
  alias Defdo.TailwindBuilder.{
    Downloader,
    PluginManager,
    Builder,
    Deployer,
    VersionFetcher,
    DefaultConfigProvider
  }

  @tailwind_latest "4.1.13"

  # Keep the same constants for compatibility
  @available_plugins %{
    "daisyui" => %{
      "version" => ~s["daisyui": "^4.12.23"],
      "statement" => ~s['daisyui': require('daisyui')]
    },
    "daisyui_v5" => %{
      "version" => ~s["daisyui": "^5.1.10"],
      "statement" => ~s['daisyui': require('daisyui')]
    }
  }

  @supported_packages %{
    "daisyui" => %{
      npm_name: "daisyui",
      description: "Semantic component classes for Tailwind CSS"
    }
  }

  @doc """
  Downloads Tailwind CSS source code.

  Migrated to use the new Downloader module.
  """
  def download(tailwind_src \\ File.cwd!(), tailwind_version \\ @tailwind_latest) do
    if not installed?("tar") do
      raise "Ensure that `tar` is installed."
    end

    Logger.info("Downloading Tailwind v#{tailwind_version} using new modular architecture")

    # Get expected checksum from ConfigProvider
    config = DefaultConfigProvider
    expected_checksum = get_expected_checksum(tailwind_version, config)

    case Downloader.download_and_extract([
      version: tailwind_version,
      destination: tailwind_src,
      expected_checksum: expected_checksum
    ]) do
      {:ok, _download_result} ->
        Logger.debug("\nExtracted files in #{tailwind_src}:")

        # Maintain the same result format as the original API
        result = %{
          root: tailwind_src,
          version: tailwind_version
        }

        {:ok, result}

      {:error, {_step, error}} ->
        Logger.error("Download failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Gets the latest version of Tailwind CSS.

  Migrated to use the new VersionFetcher module.
  """
  def get_latest_tailwind_version do
    case VersionFetcher.get_latest_tailwind_version() do
      {:ok, version} ->
        Logger.info("Latest Tailwind CSS version: #{version}")
        {:ok, version}
    end
  end

  @doc """
  Gets the latest version of an NPM package.

  Migrated to use the new VersionFetcher module.
  """
  def get_latest_npm_version(package_name) when is_binary(package_name) do
    case Map.get(@supported_packages, package_name) do
      nil ->
        {:error, :package_not_supported}

      %{npm_name: npm_name} ->
        case VersionFetcher.get_latest_npm_version(npm_name) do
          {:ok, version} ->
            Logger.info("Latest #{package_name} version: #{version}")
            {:ok, version}
          {:error, reason} ->
            Logger.warning("Failed to fetch latest #{package_name} version: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Gets information about all supported packages.

  Migrated to use the new VersionFetcher module.
  """
  def get_supported_packages_info do
    package_names = Map.keys(@supported_packages)

    case VersionFetcher.get_packages_info(package_names) do
      {:ok, packages_info} ->
        # Combine with local information from @supported_packages
        for {package_name, info} <- @supported_packages do
          version_info = Map.get(packages_info, package_name, %{latest_version: :unknown})
          {package_name, Map.merge(info, version_info)}
        end
        |> Enum.into(%{})
    end
  end

  @doc """
  Calculates checksum for a new Tailwind version.

  Migrated to use the new VersionFetcher module.
  """
  def calculate_tailwind_checksum(version) do
    VersionFetcher.calculate_tailwind_checksum(version)
  end

  @doc """
  Adds a supported package.

  Migrated to use the new VersionFetcher module.
  """
  def add_supported_package(package_name, npm_name, description) when is_binary(package_name) do
    case VersionFetcher.get_latest_npm_version(npm_name) do
      {:ok, version} ->
        Logger.info("Package #{package_name} (#{npm_name}) validated successfully")
        Logger.info("Latest version: #{version}")

        package_info = %{
          npm_name: npm_name,
          description: description,
          latest_version: version
        }

        {:ok, package_info}

      {:error, reason} ->
        Logger.error("Package #{npm_name} not found on NPM: #{inspect(reason)}")
        {:error, :package_not_found}
    end
  end

  @doc """
  Compiles Tailwind source code.

  Migrated to use the new Builder module.
  """
  def build(tailwind_version \\ @tailwind_latest, tailwind_src \\ File.cwd!(), debug \\ false) do
    Logger.info("Building Tailwind v#{tailwind_version} using new modular architecture")

    case Builder.compile([
      version: tailwind_version,
      source_path: tailwind_src,
      debug: debug
    ]) do
      {:ok, build_result} ->
        # Maintain the same result format as the original API
        result = %{
          root: tailwind_src,
          version: tailwind_version,
          tailwind_root: build_result.tailwind_root,
          tailwind_standalone_root: build_result.standalone_root
        }

        {:ok, result}

      {:error, {step, error}} ->
        case error do
          {:missing_tools, tools} ->
            {:error, "Ensure that `#{Enum.join(tools, "`, `")}` is installed."}
          {:command_failed, code, output} ->
            Logger.error("Command failed at step #{inspect(step)} with exit code #{code}")
            Logger.error("Output: #{String.slice(output, 0, 1000)}")
            {:error, "Build failed at step #{inspect(step)} with exit code #{code}. Check logs for details."}
          {message, code} when is_integer(code) ->
            Logger.error("Step #{inspect(step)} failed: #{inspect(message)}")
            {:error, "There is an error detected during the step #{inspect(step)}. with exit code: #{code}, check logs to detect issues."}
          other ->
            Logger.error("Build failed with error: #{inspect(other)}")
            {:error, "Build failed: #{inspect(other)}"}
        end
    end
  end

  @doc """
  Deploys binaries to R2.

  Migrated to use the new Deployer module.
  """
  def deploy_r2(tailwind_version \\ @tailwind_latest, tailwind_src \\ File.cwd!(), bucket \\ "defdo") do
    Logger.info("Deploying Tailwind v#{tailwind_version} using new modular architecture")

    case Deployer.deploy([
      version: tailwind_version,
      source_path: tailwind_src,
      destination: :r2,
      bucket: bucket,
      prefix: "tailwind_cli_daisyui"
    ]) do
      {:ok, deploy_result} ->
        Logger.info("Deployment successful: #{deploy_result.binaries_deployed} files deployed")
        # Maintain the same result as the original API: list of upload responses
        # Extract upload_result from each {:ok, metadata} tuple to maintain compatibility
        Enum.map(deploy_result.deployed_files, fn
          {:ok, metadata} -> metadata.upload_result
          other -> other
        end)

      {:error, {_step, error}} ->
        Logger.error("Deployment failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Applies a plugin to Tailwind code.

  Migrated to use the new PluginManager module.
  """
  def add_plugin(plugin, tailwind_version \\ @tailwind_latest, root_path \\ File.cwd!())

  def add_plugin(plugin_name, tailwind_version, root_path) when is_map_key(@available_plugins, plugin_name) do
    Logger.info("Applying plugin #{plugin_name} using new modular architecture")

    plugin_spec = @available_plugins[plugin_name]

    case PluginManager.apply_plugin(plugin_spec, [
      version: tailwind_version,
      base_path: root_path,
      plugin_name: plugin_name
    ]) do
      {:ok, plugin_result} ->
        # Return list of results like the original API
        plugin_result.patch_results

      {:error, {_step, error}} ->
        Logger.error("Plugin application failed: #{inspect(error)}")
        {:error, error}
    end
  end

  def add_plugin(plugin, tailwind_version, root_path) when is_map_key(plugin, "version") do
    Logger.info("Applying custom plugin using new modular architecture")

    case PluginManager.apply_plugin(plugin, [
      version: tailwind_version,
      base_path: root_path
    ]) do
      {:ok, plugin_result} ->
        plugin_result.patch_results

      {:error, {_step, error}} ->
        case error do
          {:invalid_version_format, _} ->
            raise """
            Be sure that you have a valid values

            The version must be a valid `package.json` entry.
            """
          {:error, {:invalid_version_format, _}} ->
            raise """
            Be sure that you have a valid values

            The version must be a valid `package.json` entry.
            """
          other ->
            Logger.error("Plugin application failed: #{inspect(other)}")
            {:error, other}
        end
    end
  end

  # Helper functions that remain the same but can use the new modules

  @doc """
  Checks if a program is installed.
  """
  def installed?(program) do
    Builder.tool_available?(program)
  end

  @doc """
  Builds the path for a file in the Tailwind directory.
  """
  def path_for(tailwind_src, tailwind_version, filename, relative_path \\ "") do
    # Use the Builder to get the correct paths
    case Builder.get_build_paths(tailwind_src, tailwind_version) do
      {:ok, paths} ->
        case relative_path do
          "src" -> Path.join([paths.standalone_root, relative_path, filename])
          "" -> Path.join(paths.standalone_root, filename)
          _ -> Path.join([paths.standalone_root, relative_path, filename])
        end

      {:error, _} ->
        # Fallback to original logic
        base_path = if Version.compare(tailwind_version, "4.0.0") in [:eq, :gt] do
          Path.join([tailwind_src, "tailwindcss-#{tailwind_version}", "packages", "@tailwindcss-standalone"])
        else
          Path.join([tailwind_src, "tailwindcss-#{tailwind_version}", "standalone-cli"])
        end

        Path.join([base_path, relative_path, filename])
    end
  end

  @doc """
  Returns the first path from a list of matches.
  """
  def maybe_path(path) do
    path |> Path.wildcard() |> List.first()
  end

  @doc """
  Gets the path to the standalone CLI directory.
  """
  def standalone_cli_path(tailwind_src, tailwind_version) do
    case Builder.get_build_paths(tailwind_src, tailwind_version) do
      {:ok, paths} -> paths.standalone_root
      {:error, _} ->
        # Fallback to original logic
        if Version.compare(tailwind_version, "4.0.0") in [:eq, :gt] do
          Path.join([tailwind_src, "tailwindcss-#{tailwind_version}", "packages/@tailwindcss-standalone"])
        else
          Path.join([tailwind_src, "tailwindcss-#{tailwind_version}", "standalone-cli"])
        end
    end
  end

  @doc """
  Gets the path to the Tailwind base directory.
  """
  def tailwind_path(tailwind_src, tailwind_version) do
    case Builder.get_build_paths(tailwind_src, tailwind_version) do
      {:ok, paths} -> paths.tailwind_root
      {:error, _} ->
        # Fallback to original logic
        Path.join([tailwind_src, "tailwindcss-#{tailwind_version}"])
    end
  end

  @doc """
  Applies patch to package.json.

  Migrated to use the new PluginManager module.
  """
  def patch_package_json(content, plugin, tailwind_version) do
    plugin_spec = %{"version" => plugin}

    case PluginManager.patch_file_content(content, plugin_spec, "package.json", tailwind_version) do
      {:ok, new_content} -> new_content
      new_content when is_binary(new_content) -> new_content
      error -> error
    end
  end

  @doc """
  Applies patch to standalone.js.

  Migrated to use the new PluginManager module.
  """
  def patch_standalone_js(content, statement) do
    # Use the PluginManager directly with the same logic as original
    if content =~ statement do
      Logger.info("It's previously patched, we don't patch it again")
      content
    else
      patch_string_at = """
      let localModules = {
      """

      case patch_content_legacy(content, patch_string_at, statement, "  ") do
        {:ok, new_content} -> new_content
        error -> error
      end
    end
  end

  @doc """
  Applies patch to index.ts.

  Migrated to use the new PluginManager module.
  """
  def patch_index_ts(content, plugin_name) do
    plugin_spec = %{"version" => ~s["#{plugin_name}": "latest"]}

    case PluginManager.patch_file_content(content, plugin_spec, "index.ts", "4.1.11") do
      {:ok, new_content} -> new_content
      new_content when is_binary(new_content) -> new_content
      error -> error
    end
  end

  # Private helper functions

  defp get_expected_checksum(version, config_provider) do
    checksums = config_provider.get_known_checksums()
    Map.get(checksums, version)
  end

  # Legacy function to maintain exact compatibility with original code
  defp patch_content_legacy(content, string_to_split_on, patch_text, spacer, add_comma \\ true) do
    case split_with_self_legacy(content, string_to_split_on) do
      {beginning, splitter, rest} ->
        order_parts = if add_comma do
          [beginning, splitter, spacer, patch_text, ?,, ?\n, rest]
        else
          [beginning, splitter, spacer, patch_text, ?\n, rest]
        end

        new_content = IO.iodata_to_binary(order_parts)
        {:ok, new_content}

      _ ->
        {:error, :unable_to_patch}
    end
  end

  defp split_with_self_legacy(contents, text) do
    case :binary.split(contents, text) do
      [left, right] -> {left, text, right}
      [_] -> :error
    end
  end
end
