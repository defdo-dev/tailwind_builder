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

  @tailwind_latest "3.3.0"
  @available_plugins %{
    "daisyui" => %{
      "version" => ~s["daisyui": "^2.51.5"],
      "statement" => ~s['daisyui': require('daisyui')]
    }
  }

  def download(tailwind_src \\ File.cwd!(), tailwind_version \\ @tailwind_latest) do
    tar = "tar"

    if is_installed?("tar") do
      repo = "tailwindcss"
      release_package = "#{tailwind_version}.tar.gz"
      downloaded_tar_file = Path.join(tailwind_src, release_package)
      url = "https://github.com/tailwindlabs/#{repo}/archive/refs/tags/v#{release_package}"

      with {:filename, true} <- {:filename, maybe_download(downloaded_tar_file, url)},
           {:untar, :ok} <- {:untar, untar(downloaded_tar_file)},
           {:clean_tmp, :ok} <- {:clean_tmp, File.rm!(downloaded_tar_file)} do
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
      :erl_tar.extract(path_tar_file, [:compressed])
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
  def build(tailwind_src \\ File.cwd!(), tailwind_version \\ @tailwind_latest) do
    npm = "npm"

    tailwind_root =
      tailwind_src
      |> tailwind_path(tailwind_version)
      |> maybe_path() ||
        raise "Ensure that you are pointing to the tailwind source; we can't find the standalone-cli directory"

    standalone_root =
      tailwind_src
      |> standalone_cli_path(tailwind_version)
      |> maybe_path()

    Logger.debug(tailwind_root, label: "tailwind_root")
    Logger.debug(standalone_root, label: "standalone_root")

    with {:npm, true} <- {:npm, is_installed?(npm)},
         {:env_swap_engine, {_, 0}} <-
           {:env_swap_engine,
            System.cmd("node", ["./scripts/swap-engines.js"], cd: tailwind_root, into: IO.stream())},
         {:env_setup_install, {_, 0}} <-
           {:env_setup_install,
            System.cmd(npm, ["install"], cd: tailwind_root, into: IO.stream())},
         {:env_setup_build, {_, 0}} <-
           {:env_setup_build,
            System.cmd(npm, ["run", "build"], cd: tailwind_root, into: IO.stream())},
         {:install_deps, {_, 0}} <-
           {:install_deps, System.cmd(npm, ["install"], cd: standalone_root, into: IO.stream())},
         {:build_target, {_, 0}} <-
           {:build_target,
            System.cmd(npm, ["run", "build"], cd: standalone_root, into: IO.stream())} do
      result = %{
        root: tailwind_src,
        version: tailwind_version,
        tailwind_root: tailwind_root,
        tailwind_standalone_root: standalone_root
      }

      {:ok, result}
    else
      {:npm, false} ->
        {:error, "Ensure that `#{npm}` is installed."}

      {step, {message, code}} ->
        Logger.error([inspect(message)])

        {:error,
         "There is an error detected during the step #{step}. with exit code: #{code}, check logs to detect issues."}
    end
  end

  def deploy(tailwind_src \\ File.cwd!(), tailwind_version \\ @tailwind_latest) do
    # working_dir =
    tailwind_src
    |> standalone_cli_path(tailwind_version)
    |> Path.join("dist")
    |> maybe_path() || raise "Ensure that you `build` first"
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
      when is_map_key(plugin, "version") and is_map_key(plugin, "statement") do
    if plugin["version"] =~ ":" and plugin["statement"] =~ ":" do
      plugin_name =
        plugin["version"] |> String.split(":") |> List.first() |> String.replace("\"", "")

      apply_patch(tailwind_version, plugin_name, plugin, root_path)
    else
      raise """
      Be sure that you have a valid values

      The version must be a valid `package.json` entry.
      The statement must be a valid js object.
      """
    end
  end

  defp apply_patch(tailwind_version, plugin_name, plugin, root_path) do
    for filename <- ~w(package.json standalone.js) do
      Logger.debug(["Patching ", filename, " with plugin ", plugin_name])

      content =
        tailwind_version
        |> read_content(filename, root_path)
        |> patch_content(filename, plugin)

      with :ok <- write_content(tailwind_version, filename, content, root_path) do
        "Patch to #{filename} was applied."
      else
        error -> error
      end
    end
  end

  defp read_content(tailwind_version, filename, root_path) do
    root_path
    |> path_for(tailwind_version, filename)
    |> File.read!()
  end

  defp write_content(tailwind_version, filename, content, root_path) do
    root_path
    |> path_for(tailwind_version, filename)
    |> File.write!(content)
  end

  defp patch_content(content, "package.json", plugin) do
    patch_package_json(content, plugin["version"])
  end

  defp patch_content(content, "standalone.js", plugin) do
    patch_standalone_js(content, plugin["statement"])
  end

  # Helpers
  @doc api: :low
  def is_installed?(program) do
    if System.find_executable("#{program}"), do: true, else: false
  end

  @doc """
  Get the path for a file in a root directory

  The tailwind_src directory must contain the source code of tailwind.
  """
  @doc api: :low
  def path_for(tailwind_src, tailwind_version, filename) do
    tailwind_src
    |> standalone_cli_path(tailwind_version)
    |> Path.join(filename)
    |> maybe_path()
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
    Path.join(tailwind_src, "/*-#{tailwind_version}/standalone-cli")
  end

  @doc api: :low
  def tailwind_path(tailwind_src, tailwind_version) do
    Path.join(tailwind_src, "/*-#{tailwind_version}")
  end

  @doc """
  Do the package.json patch
  """
  @doc api: :low
  def patch_package_json(content, plugin) do
    if content =~ plugin do
      Logger.info("It's previously patched, we don't do it again")
      content
    else
      patch_string_at = """
      "devDependencies": {
      """

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

  defp patch(content, string_to_split_on, patch_text, spacer) do
    case split_with_self(content, string_to_split_on) do
      {beginning, splitter, rest} ->
        new_content =
          IO.iodata_to_binary([beginning, splitter, spacer, patch_text, ?,, ?\n, rest])

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
