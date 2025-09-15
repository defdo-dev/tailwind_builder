defmodule Defdo.TailwindBuilderOriginal do
  @moduledoc """
  Build your own custom tailwind cli.

  Add personalized plugins following simple rules, our use our configured plugins.

  Our Steps
  - [x] Download the source code for tailwindcss
  - [x] Patch the files to add a plugin
  - [x] Compile the source to get the target binaries (Ensure that you first add your plugins)
  - [ ] Optional deploy to s3 repository.
  """
  require Logger

  @tailwind_latest "4.1.13"
  @available_plugins %{
    "daisyui" => %{
      "version" => ~s["daisyui": "^4.12.23"],
      "statement" => ~s['daisyui': require('daisyui')]
    },
    "daisyui_v5" => %{
      "version" => ~s["daisyui": "^5.1.10"]
    }
  }

  # Supported NPM packages for dynamic version fetching
  # Only include external plugins (not built-in Tailwind features)
  @supported_packages %{
    "daisyui" => %{
      npm_name: "daisyui",
      description: "Semantic component classes for Tailwind CSS"
    }
  }

  def download(tailwind_src \\ File.cwd!(), tailwind_version \\ @tailwind_latest) do
    tar = "tar"

    if installed?("tar") do
      repo = "tailwindcss"
      release_package = "#{tailwind_version}.tar.gz"
      downloaded_tar_file = Path.join(tailwind_src, release_package)
      url = "https://github.com/tailwindlabs/#{repo}/archive/refs/tags/v#{release_package}"

      with {:filename, true} <- {:filename, download_gh_tailwind(downloaded_tar_file, url, tailwind_version)},
           {:untar, :ok} <- {:untar, untar(downloaded_tar_file)},
           {:clean_tmp, :ok} <- {:clean_tmp, File.rm!(downloaded_tar_file)} do
        # Add debug info
        Logger.debug("\nExtracted files in #{tailwind_src}:")

        result = %{
          root: tailwind_src,
          version: tailwind_version
        }

        {:ok, result}
      else
        error ->
          Logger.error([inspect(error)])
          error
      end
    else
      raise "Ensure that `#{tar}` is installed."
    end
  end

  # Known checksums for Tailwind releases (SHA256)
  @tailwind_checksums %{
    "3.4.17" => "89c0a7027449cbe564f8722e84108f7bfa0224b5d9289c47cc967ffef8e1b016",
    "4.0.9" => "7c36fdcdfed4d1b690a56a1267457a8ac9c640ccae2efcaed59f5053d330000a",
    "4.0.17" => "3590bcb90a75c32ba8b10d692d26838caedbc267a57db23931694abc9598c873",
    "4.1.11" => "149b7db8417a4a0419ada1d2dc428a11202fc6b971f037b7a8527371c59e0cae"
    # Future: Add checksums as they become available from official releases
  }

  defp download_gh_tailwind(path, url, version) do
    if not File.exists?(path) do
      # Validate URL before downloading
      if not validate_github_url(url) do
        Logger.warning("Invalid GitHub URL: #{url}. Only official Tailwind CSS releases are allowed.")
        false
      else
        # Download the file
        content_binary = fetch_body!(url)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, content_binary, [:binary])
        File.chmod(path, 0o755)

        # Validate download integrity
        validate_download_integrity(content_binary, version, url)

        File.exists?(path)
      end
    else
      File.exists?(path)
    end
  end

  defp validate_github_url(url) do
    String.match?(url, ~r{^https://github\.com/tailwindlabs/tailwindcss/archive/refs/tags/v\d+\.\d+\.\d+\.tar\.gz$})
  end

  defp untar(path_tar_file) do
    if File.exists?(path_tar_file) do
      Logger.debug("Extracting #{path_tar_file}")

      case :erl_tar.extract(path_tar_file, [:compressed, {:cwd, Path.dirname(path_tar_file)}]) do
        :ok ->
          Logger.info("Extraction successful")
          :ok

        error ->
          Logger.error("Extraction failed: #{inspect(error)}")
          error
      end
    else
      {:error, "#{path_tar_file} is an invalid path."}
    end
  end

  defp fetch_body!(url) do
    url_string = to_string(url)
    url_charlist = String.to_charlist(url_string)
    Logger.debug("Downloading from #{url_string}")

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    if proxy = System.get_env("HTTP_PROXY") || System.get_env("http_proxy") do
      Logger.debug("Using HTTP_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:proxy, {{String.to_charlist(host), port}, []}}])
    end

    if proxy = System.get_env("HTTPS_PROXY") || System.get_env("https_proxy") do
      Logger.debug("Using HTTPS_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:https_proxy, {{String.to_charlist(host), port}, []}}])
    end

    # https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/inets
    cacertfile = CAStore.file_path() |> String.to_charlist()

    http_options = [
      ssl: [
        verify: :verify_peer,
        cacertfile: cacertfile,
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ],
        versions: protocol_versions()
      ]
    ]

    options = [body_format: :binary]

    case :httpc.request(:get, {url_charlist, []}, http_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body

      {:ok, {{_, status, _}, _headers, _body}} ->
        raise "HTTP error #{status} while downloading #{url_string}"

      {:error, reason} ->
        raise "Network error while downloading #{url_string}: #{inspect(reason)}"

      other ->
        raise "Unexpected response while downloading #{url_string}: #{inspect(other)}"
    end
  end

  defp validate_download_integrity(body, version, url) do
    size = byte_size(body)

    # Basic size sanity check (not for security, just to catch obvious issues)
    min_size = 100 * 1024  # 100KB
    max_size = 200 * 1024 * 1024  # 200MB

    if size < min_size do
      Logger.warning("Downloaded file seems very small (#{size} bytes) for #{url}")
    end

    if size > max_size do
      Logger.warning("Downloaded file seems very large (#{size} bytes) for #{url}")
    end

    # Validate checksum if available
    case validate_checksum(body, version) do
      :ok ->
        Logger.debug("Download integrity validated: #{size} bytes, checksum verified for version #{version}")

      :no_checksum ->
        Logger.warning("No checksum available for version #{version}. Consider adding to @tailwind_checksums")
        Logger.debug("Download completed: #{size} bytes for version #{version}")

      {:error, :checksum_mismatch} ->
        Logger.error("CHECKSUM MISMATCH for version #{version}! Downloaded file may be corrupted or tampered with.")
        Logger.error("Expected checksum from @tailwind_checksums, but calculated checksum differs.")
        # Don't raise - log the issue but continue (user can decide)
    end
  end

  defp validate_checksum(body, version) do
    case Map.get(@tailwind_checksums, version) do
      nil ->
        :no_checksum

      expected_checksum ->
        actual_checksum =
          :crypto.hash(:sha256, body)
          |> Base.encode16(case: :lower)

        if actual_checksum == expected_checksum do
          :ok
        else
          Logger.debug("Expected: #{expected_checksum}")
          Logger.debug("Actual:   #{actual_checksum}")
          {:error, :checksum_mismatch}
        end
    end
  end


  defp protocol_versions do
    if otp_version() < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
  end

  defp otp_version do
    :erlang.system_info(:otp_release) |> List.to_integer()
  end

  @doc """
  Get the latest version of Tailwind CSS from GitHub API
  """
  def get_latest_tailwind_version do
    case fetch_github_latest_release("tailwindlabs", "tailwindcss") do
      {:ok, version} ->
        Logger.info("Latest Tailwind CSS version: #{version}")
        {:ok, version}
      {:error, reason} ->
        Logger.warning("Failed to fetch latest Tailwind version: #{inspect(reason)}")
        Logger.info("Using default version: #{@tailwind_latest}")
        {:ok, @tailwind_latest}
    end
  end

  @doc """
  Get the latest version of an NPM package
  """
  def get_latest_npm_version(package_name) when is_binary(package_name) do
    case Map.get(@supported_packages, package_name) do
      nil ->
        {:error, :package_not_supported}

      %{npm_name: npm_name} ->
        case fetch_npm_latest_version(npm_name) do
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
  Get all supported packages with their latest versions
  """
  def get_supported_packages_info do
    for {package_name, info} <- @supported_packages do
      case get_latest_npm_version(package_name) do
        {:ok, version} ->
          {package_name, Map.put(info, :latest_version, version)}
        {:error, _} ->
          {package_name, Map.put(info, :latest_version, :unknown)}
      end
    end
    |> Enum.into(%{})
  end

  defp fetch_github_latest_release(owner, repo) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/releases/latest"

    case fetch_json_api(url) do
      {:ok, %{"tag_name" => tag_name}} ->
        # Remove 'v' prefix if present (e.g., "v3.4.17" -> "3.4.17")
        version = String.replace_prefix(tag_name, "v", "")
        {:ok, version}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_npm_latest_version(package_name) do
    url = "https://registry.npmjs.org/#{package_name}/latest"

    case fetch_json_api(url) do
      {:ok, %{"version" => version}} ->
        {:ok, version}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_json_api(url) do
    try do
      case fetch_body!(url) do
        body when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, data} -> {:ok, data}
            {:error, reason} -> {:error, {:json_decode_error, reason}}
          end
        error ->
          {:error, {:fetch_error, error}}
      end
    rescue
      error ->
        {:error, {:exception, error}}
    end
  end

  @doc """
  Calculate and suggest checksum for a new Tailwind version
  This helps maintainers add new versions to @tailwind_checksums
  """
  def calculate_tailwind_checksum(version) do
    url = "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v#{version}.tar.gz"

    if not validate_github_url(url) do
      {:error, :invalid_url}
    else
      try do
        Logger.info("Downloading Tailwind v#{version} to calculate checksum...")
        content_binary = fetch_body!(url)
        checksum =
          :crypto.hash(:sha256, content_binary)
          |> Base.encode16(case: :lower)

        size = byte_size(content_binary)
        Logger.info("Calculated checksum for Tailwind v#{version}:")
        Logger.info("  Size: #{size} bytes")
        Logger.info("  SHA256: #{checksum}")
        Logger.info("Add this to @tailwind_checksums:")
        Logger.info(~s[  "#{version}" => "#{checksum}"])

        {:ok, %{version: version, checksum: checksum, size: size}}
      rescue
        error ->
          Logger.error("Failed to calculate checksum for v#{version}: #{inspect(error)}")
          {:error, {:calculation_failed, error}}
      end
    end
  end

  @doc """
  Update supported packages list dynamically
  """
  def add_supported_package(package_name, npm_name, description) when is_binary(package_name) do
    # This would typically update a configuration file or database
    # For now, we'll just validate and return what would be added
    package_info = %{
      npm_name: npm_name,
      description: description
    }

    case get_latest_npm_version(package_name) do
      {:ok, version} ->
        Logger.info("Package #{package_name} (#{npm_name}) validated successfully")
        Logger.info("Latest version: #{version}")
        {:ok, Map.put(package_info, :latest_version, version)}

      {:error, :package_not_supported} ->
        # Try to fetch directly from NPM to validate it exists
        case fetch_npm_latest_version(npm_name) do
          {:ok, version} ->
            Logger.info("New package #{package_name} (#{npm_name}) found")
            Logger.info("Latest version: #{version}")
            Logger.info("Add to @supported_packages:")
            Logger.info(~s["#{package_name}" => %{npm_name: "#{npm_name}", description: "#{description}"}])
            {:ok, Map.put(package_info, :latest_version, version)}

          {:error, reason} ->
            Logger.error("Package #{npm_name} not found on NPM: #{inspect(reason)}")
            {:error, :package_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build the distribution source

  > It requires npm is installed on the builder system.
  """
  def build(tailwind_version \\ @tailwind_latest, tailwind_src \\ File.cwd!(), debug \\ false) do
    tailwind_root =
      tailwind_src
      |> tailwind_path(tailwind_version)
      |> maybe_path() ||
        raise "Ensure that you are pointing to the tailwind source"

    standalone_root =
      tailwind_src
      |> standalone_cli_path(tailwind_version)
      |> maybe_path()

    version =
      if Version.compare(tailwind_version, "4.0.0") in [:eq, :gt] do
        :v4
      else
        :v3
      end

    case build_version(version, tailwind_root, standalone_root, debug) do
      :ok ->
        result = %{
          root: tailwind_src,
          version: tailwind_version,
          tailwind_root: tailwind_root,
          tailwind_standalone_root: standalone_root
        }

        {:ok, result}

      {:error, message} ->
        {:error, message}
    end
  end

  defp build_version(:v3, tailwind_root, standalone_root, debug) do
    pkg_manager = "npm"

    with {:pkg_manager, true} <- {:pkg_manager, installed?(pkg_manager)},
         # Install core dependencies
         {:root_install, {_output, 0}} <-
           {:root_install,
            if debug do
              System.cmd(pkg_manager, ["install"], cd: tailwind_root)
            else
              # Capture output instead of sending to /dev/null
              System.cmd(pkg_manager, ["install"], cd: tailwind_root, stderr_to_stdout: true)
            end},
         # Build the project
         {:root_build, {_output, 0}} <-
           {:root_build,
            if debug do
              System.cmd(pkg_manager, ["run", "build"], cd: tailwind_root)
            else
              # Capture output instead of sending to /dev/null
              System.cmd(pkg_manager, ["run", "build"], cd: tailwind_root, stderr_to_stdout: true)
            end},
         {:standalone_install, {_output, 0}} <-
           {:standalone_install,
            if debug do
              System.cmd(pkg_manager, ["install"], cd: standalone_root)
            else
              # Capture output instead of sending to /dev/null
              System.cmd(pkg_manager, ["install"], cd: standalone_root, stderr_to_stdout: true)
            end},
         {:standalone_build, {_, 0}} <-
           {:standalone_build,
            if debug do
              System.cmd(pkg_manager, ["run", "build"], cd: standalone_root)
            else
              # Capture output instead of sending to /dev/null
              System.cmd(pkg_manager, ["run", "build"],
                cd: standalone_root,
                stderr_to_stdout: true
              )
            end} do
      :ok
    else
      {:pkg_manager, false} ->
        {:error, "Ensure that `#{pkg_manager}` is installed."}

      {step, {message, code}} ->
        Logger.error([inspect(message)])

        {:error,
         "There is an error detected during the step #{step}. with exit code: #{code}, check logs to detect issues."}
    end
  end

  defp build_version(:v4, tailwind_root, standalone_root, debug) do
    pkg_manager = "pnpm"

    with {:pkg_manager, true} <- {:pkg_manager, installed?(pkg_manager)},
         # Install core dependencies
         {:root_install, {_output, 0}} <-
           {:root_install,
            if debug do
              System.cmd(pkg_manager, ["install", "--no-frozen-lockfile"], cd: tailwind_root)
            else
              # Capture output instead of sending to /dev/null
              System.cmd(pkg_manager, ["install", "--no-frozen-lockfile"],
                cd: tailwind_root,
                stderr_to_stdout: true
              )
            end},
         # Build the project
         {:root_build, {_output, 0}} <-
           {:root_build,
            if debug do
              System.cmd(pkg_manager, ["run", "build"], cd: tailwind_root)
            else
              # Capture output instead of sending to /dev/null
              System.cmd(pkg_manager, ["run", "build"],
                cd: tailwind_root,
                stderr_to_stdout: true
              )
            end},
         # we need to rebuild at standalone level to get the correct bundle
         # otherwise the bundle throughs the error:
         # Cannot require module @tailwindcss/oxide-darwin-arm64
         {:rebuild_standalone, {_output, 0}} <-
           {:rebuild_standalone,
            if debug do
              System.cmd(pkg_manager, ["run", "build"], cd: standalone_root)
            else
              # Capture output instead of sending to /dev/null
              System.cmd(pkg_manager, ["run", "build"],
                cd: standalone_root,
                stderr_to_stdout: true
              )
            end} do
      :ok
    else
      {:pkg_manager, false} ->
        {:error, "Ensure that `#{pkg_manager}` is installed."}

      {step, {message, code}} ->
        Logger.error([inspect(message)])

        {:error,
         "There is an error detected during the step #{step}. with exit code: #{code}, check logs to detect issues."}
    end
  end

  def deploy_r2(
        tailwind_version \\ @tailwind_latest,
        tailwind_src \\ File.cwd!(),
        bucket \\ "defdo"
      ) do
    working_dir =
      tailwind_src
      |> standalone_cli_path(tailwind_version)
      |> Path.join("dist")
      |> maybe_path() || raise "Ensure that you `build` first"

    to_distribute =
      working_dir
      |> Path.join("/tailwindcss*")
      |> Path.wildcard()

    for file_path <- to_distribute do
      filename = Path.basename(file_path)
      object = "tailwind_cli_daisyui/v#{tailwind_version}/#{filename}"

      file_path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(bucket, object)
      |> ExAws.request!()
    end
  end

  @doc """
  Adds an available plugin
  """
  @doc api: :high
  def add_plugin(plugin, tailwind_version \\ @tailwind_latest, root_path \\ File.cwd!())

  def add_plugin(plugin_name, tailwind_version, root_path)
      when is_map_key(@available_plugins, plugin_name) do
    plugin = @available_plugins[plugin_name]
    apply_patch(tailwind_version, plugin_name, plugin, root_path)
  end

  def add_plugin(plugin, tailwind_version, root_path)
      when is_map_key(plugin, "version") do
    if plugin["version"] =~ ":" do
      plugin_name =
        plugin["version"] |> String.split(":") |> List.first() |> String.replace("\"", "")

      apply_patch(tailwind_version, plugin_name, plugin, root_path)
    else
      raise """
      Be sure that you have a valid values

      The version must be a valid `package.json` entry.
      """
    end
  end

  defp apply_patch(tailwind_version, plugin_name, plugin, root_path) do
    files =
      if Version.compare(tailwind_version, "4.0.0") in [:eq, :gt] do
        # ~w(package.json src/index.ts)
        [{"", "package.json"}, {"src", "index.ts"}]
      else
        [{"", "package.json"}, {"", "standalone.js"}]
      end

    for {relative_path, filename} <- files do
      Logger.debug(["Patching ", filename, " with plugin ", plugin_name])

      content =
        tailwind_version
        |> read_content(filename, root_path, relative_path)
        |> patch_content(filename, plugin, tailwind_version)

      with :ok <- write_content(tailwind_version, filename, content, root_path, relative_path) do
        "Patch to #{filename} was applied."
      else
        error -> error
      end
    end
  end

  defp read_content(tailwind_version, filename, root_path, relative_path) do
    path = path_for(root_path, tailwind_version, filename, relative_path)

    if path && File.exists?(path) do
      File.read!(path)
    else
      raise "File not found: #{filename} in path: #{root_path}"
    end
  end

  defp write_content(tailwind_version, filename, content, root_path, relative_path) do
    root_path
    |> path_for(tailwind_version, filename, relative_path)
    |> File.write!(content)
  end

  defp patch_content(content, "package.json", plugin, tailwind_version) do
    patch_package_json(content, plugin["version"], tailwind_version)
  end

  defp patch_content(content, "standalone.js", plugin, _tailwind_version) do
    patch_standalone_js(content, plugin["statement"])
  end

  defp patch_content(content, "index.ts", plugin, _tailwind_version) do
    plugin_name =
      plugin["version"] |> String.split(":") |> List.first() |> String.replace("\"", "")

    patch_index_ts(content, plugin_name)
  end

  # Helpers
  @doc api: :low
  def installed?(program) do
    if System.find_executable("#{program}"), do: true, else: false
  end

  @doc """
  Get the path for a file in a root directory

  The tailwind_src directory must contain the source code of tailwind.
  """
  @doc api: :low
  def path_for(tailwind_src, tailwind_version, filename, relative_path \\ "") do
    base_path =
      if Version.compare(tailwind_version, "4.0.0") in [:eq, :gt] do
        Path.join([
          tailwind_src,
          "tailwindcss-#{tailwind_version}",
          "packages",
          "@tailwindcss-standalone"
        ])
      else
        Path.join([
          tailwind_src,
          "tailwindcss-#{tailwind_version}",
          "standalone-cli"
        ])
      end

    path = Path.join([base_path, relative_path, filename])
    Logger.debug("Looking for file at: #{path}")
    path
  end

  @doc """
  Returns the first path from the list of coincidences.
  """
  def maybe_path(path) do
    path
    |> Path.wildcard()
    |> List.first()
  end

  @doc api: :low
  def standalone_cli_path(tailwind_src, tailwind_version) do
    if Version.compare(tailwind_version, "4.0.0") in [:eq, :gt] do
      Path.join([
        tailwind_src,
        "tailwindcss-#{tailwind_version}",
        "packages/@tailwindcss-standalone"
      ])
    else
      Path.join([
        tailwind_src,
        "tailwindcss-#{tailwind_version}",
        "standalone-cli"
      ])
    end
  end

  @doc api: :low
  def tailwind_path(tailwind_src, tailwind_version) do
    # Match the same pattern as standalone_cli_path
    Path.join([
      tailwind_src,
      "tailwindcss-#{tailwind_version}"
    ])
  end

  @doc """
  Do the package.json patch using JSON parsing for better reliability
  """
  @doc api: :low
  def patch_package_json(content, plugin, tailwind_version) do
    if content =~ plugin do
      Logger.info("It's previously patched, we don't do it again")
      content
    else
      patch_package_json_with_json(content, plugin, tailwind_version)
    end
  end

  defp patch_package_json_with_json(content, plugin, tailwind_version) do
    try do
      # Parse JSON
      package_json = Jason.decode!(content)

      # Determine dependency section based on version
      dep_section =
        if Version.compare(tailwind_version, "4.0.0") in [:eq, :gt] do
          "dependencies"
        else
          "devDependencies"
        end

      # Parse plugin dependency
      [plugin_name, plugin_version] = String.split(plugin, ": ", parts: 2)
      plugin_name = String.trim(plugin_name, "\"")
      plugin_version = String.trim(plugin_version, "\"")

      # Ensure dependency section exists
      package_json = Map.put_new(package_json, dep_section, %{})

      # Add plugin to appropriate section
      updated_deps = Map.put(package_json[dep_section], plugin_name, plugin_version)
      updated_package_json = Map.put(package_json, dep_section, updated_deps)

      # Convert back to formatted JSON
      Jason.encode!(updated_package_json, pretty: true)
    rescue
      error ->
        Logger.warning("JSON parsing failed for package.json: #{inspect(error)}")
        Logger.warning("Falling back to string-based patching")

        # Fallback to original string-based patching
        patch_string_at =
          if Version.compare(tailwind_version, "4.0.0") in [:eq, :gt] do
            """
            "dependencies": {
            """
          else
            """
            "devDependencies": {
            """
          end

        case patch(content, patch_string_at, plugin, "    ") do
          {:ok, new_content} -> new_content
          error -> error
        end
    end
  end

  @doc """
  Do the standalone.js patch
  """
  @doc api: :low
  def patch_standalone_js(content, statement) do
    if content =~ statement do
      Logger.info("It's previously patched, we don't patch it again")
      content
    else
      patch_string_at = """
      let localModules = {
      """

      case patch(content, patch_string_at, statement, "  ") do
        {:ok, new_content} -> new_content
        error -> error
      end
    end
  end

  @doc api: :low
  def patch_index_ts(content, plugin_name) do
    # Check if plugin is already present in any of the key sections
    already_patched? =
      content =~ ~s|id === '#{plugin_name}'| ||
        content =~ ~s|id.startsWith('#{plugin_name}/')| ||
        content =~ ~s|'#{plugin_name}': await import('#{plugin_name}')|

    if already_patched? do
      Logger.info("Plugin #{plugin_name} is already patched, skipping")
      content
    else
      # Add to the __tw_resolve id checks
      content = patch_tw_resolve(content, plugin_name)
      # Add special path handling for bundled modules
      content = patch_special_path(content, plugin_name)
      # Add to the __tw_load function
      content = patch_tw_load(content, plugin_name)
      # Add to the bundled imports
      content = patch_bundled_imports(content, plugin_name)

      content
    end
  end

  defp patch_tw_resolve(content, plugin_name) do
    patch_string_at = """
    id.startsWith('@tailwindcss/') ||
    """

    patch_text = ~s[id.startsWith('#{plugin_name}') ||]

    case patch(content, patch_string_at, patch_text, "    ", false) do
      {:ok, new_content} -> new_content
      _error -> content
    end
  end

  defp patch_special_path(content, plugin_name) do
    # Look for the line where id transformation begins
    patch_string_at = ~s[  switch (id) {]

    patch_text =
      ~s[  if (/(\\/)?#{plugin_name}(\\/.+)?$/.test(id)) { return id }
    ]

    case patch(content, patch_string_at, patch_text, "", false, :before) do
      {:ok, new_content} ->
        new_content

      _error ->
        content
    end
  end

  defp patch_tw_load(content, plugin_name) do
    patch_string_at = ~s[    return require('@tailwindcss/aspect-ratio')]

    patch_text = ~s[
  } else if (/(\\/)?#{plugin_name}(\\/.+)?$/.test(id)) {
    return require('#{plugin_name}')]

    case patch(content, patch_string_at, patch_text, "", false) do
      {:ok, new_content} -> new_content
      _error -> content
    end
  end

  defp patch_bundled_imports(content, plugin_name) do
    patch_string_at = """
      'tailwindcss/defaultTheme.js': await import('tailwindcss/defaultTheme'),
    """

    patch_text = ~s[      '#{plugin_name}': await import('#{plugin_name}'),]

    case patch(content, patch_string_at, patch_text, "", false) do
      {:ok, new_content} -> new_content
      _error -> content
    end
  end

  defp patch(
         content,
         string_to_split_on,
         patch_text,
         spacer,
         add_comma \\ true,
         insert_mode \\ :after
       ) do
    case split_with_self(content, string_to_split_on) do
      {beginning, splitter, rest} ->
        order_parts =
          if insert_mode == :before do
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

  @spec split_with_self(String.t(), String.t()) :: {String.t(), String.t(), String.t()} | :error
  defp split_with_self(contents, text) do
    case :binary.split(contents, text) do
      [left, right] -> {left, text, right}
      [_] -> :error
    end
  end
end
