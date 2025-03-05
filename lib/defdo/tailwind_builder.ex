defmodule Defdo.TailwindBuilder do
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

  @tailwind_latest "3.4.17"
  @available_plugins %{
    "daisyui" => %{
      "version" => ~s["daisyui": "^4.12.23"],
      "statement" => ~s['daisyui': require('daisyui')]
    },
    "daisyui_v5" => %{
      "version" => ~s["daisyui": "5.0.0"]
    }
  }

  def download(tailwind_src \\ File.cwd!(), tailwind_version \\ @tailwind_latest) do
    tar = "tar"

    if installed?("tar") do
      repo = "tailwindcss"
      release_package = "#{tailwind_version}.tar.gz"
      downloaded_tar_file = Path.join(tailwind_src, release_package)
      url = "https://github.com/tailwindlabs/#{repo}/archive/refs/tags/v#{release_package}"

      with {:filename, true} <- {:filename, maybe_download(downloaded_tar_file, url)},
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

  defp maybe_download(path, url) do
    if not File.exists?(path) do
      content_binary = fetch_body!(url)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content_binary, [:binary])
      File.chmod(path, 0o755)
    end

    File.exists?(path)
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
    url = String.to_charlist(url)
    Logger.debug("Downloading tailwind from #{url}")

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

    case :httpc.request(:get, {url, []}, http_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body

      other ->
        raise "couldn't fetch #{url}: #{inspect(other)}"
    end
  end

  defp protocol_versions do
    if otp_version() < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
  end

  defp otp_version do
    :erlang.system_info(:otp_release) |> List.to_integer()
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

  defp build_version(:v4, tailwind_root, _standalone_root, debug) do
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
  Do the package.json patch
  """
  @doc api: :low
  def patch_package_json(content, plugin, tailwind_version) do
    if content =~ plugin do
      Logger.info("It's previously patched, we don't do it again")
      content
    else
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
      # Add subpath imports if needed (like daisyui/theme)
      content = patch_subpath_imports(content, plugin_name)

      content
    end
  end

  defp patch_tw_resolve(content, plugin_name) do
    patch_string_at = """
    id.startsWith('@tailwindcss/') ||
    """

    patch_text = ~s[id === '#{plugin_name}' ||
    id.startsWith('#{plugin_name}/') ||]

    case patch(content, patch_string_at, patch_text, "    ", false) do
      {:ok, new_content} -> new_content
      _error -> content
    end
  end

  defp patch_special_path(content, plugin_name) do
    # Look for the line where id transformation begins
    patch_string_at = ~s[  id = id.startsWith('tailwindcss/')]

    patch_text =
      ~s[  if (id === '#{plugin_name}' || id.startsWith('#{plugin_name}/')) { return `/$bunfs/root/${id}`; }
    ]

    case patch(content, patch_string_at, patch_text, "", false, :before) do
      {:ok, new_content} ->
        new_content

      _error ->
        content
    end
  end

  defp patch_tw_load(content, plugin_name) do
    patch_string_at = ~s[globalThis.__tw_load = async (id) => {]

    patch_text = ~s[
    const realId = id.includes('/$bunfs/root/')
      ? id.replace(/^.*\\/\\$bunfs\\/root\\//, '')
      : id;]

    content =
      case patch(content, patch_string_at, patch_text, "", false) do
        {:ok, new_content} -> new_content
        _error -> content
      end

    # Now add the plugin-specific load handler
    patch_string_at = ~s[    return require('@tailwindcss/aspect-ratio')]

    patch_text = ~s[
    } else if (realId === '#{plugin_name}' || realId.startsWith('#{plugin_name}/')) {
    return require(realId);]

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

  defp patch_subpath_imports(content, plugin_name) do
    # Add common subpaths for the plugin
    subpaths =
      case plugin_name do
        "daisyui" -> ["theme"]
        _ -> []
      end

    Enum.reduce(subpaths, content, fn subpath, updated_content ->
      patch_string_at = ~s[      '#{plugin_name}': await import('#{plugin_name}'),]

      patch_text = ~s[
      '#{plugin_name}/#{subpath}': await import('#{plugin_name}/#{subpath}'),]

      case patch(updated_content, patch_string_at, patch_text, "", false) do
        {:ok, new_content} -> new_content
        _error -> updated_content
      end
    end)
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
