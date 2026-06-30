defmodule Defdo.TailwindBuilder.Release do
  @moduledoc """
  End-to-end release flow for building and publishing Tailwind standalone
  binaries with release metadata, smoke tests, and artifact manifests.
  """

  require Logger

  alias Defdo.TailwindBuilder.{
    Builder,
    Deployer,
    Downloader,
    PluginManager
  }

  alias Defdo.TailwindBuilder.ConfigProviders.ProductionConfigProvider

  @default_version "4.2.2"
  @default_release_channel "v4.2.2-rc1"
  @default_plugins ["daisyui_v5"]
  @default_storage_base_url "https://storage.defdo.de"

  @doc """
  Run the full release flow.
  """
  def run(opts \\ []) do
    opts =
      Keyword.validate!(opts, [
        :version,
        :release_channel,
        :source_path,
        :plugins,
        :config_provider,
        :destination,
        :bucket,
        :prefix,
        :storage_base_url,
        :debug,
        :validate_tools,
        :validate_binaries,
        :generate_manifest,
        :generate_checksums,
        :smoke_test_binaries,
        :smoke_test_opts,
        :storage,
        :verify_upload,
        :verification_fetcher,
        :verification_timeout,
        :verify_smoke_test,
        :dry_run,
        :overwrite_policy,
        :tailwind_version,
        :tailwind_cli_version,
        :source_checksum,
        :merge_manifest,
        :compose_targets
      ])

    version = Keyword.get(opts, :version, @default_version)
    release_channel = Keyword.get(opts, :release_channel, @default_release_channel)
    config_provider = Keyword.get(opts, :config_provider, ProductionConfigProvider)
    destination = Keyword.get(opts, :destination, :r2)
    source_path = Keyword.get(opts, :source_path, default_source_path(release_channel))
    plugins = Keyword.get(opts, :plugins, @default_plugins)
    debug = Keyword.get(opts, :debug, false)
    validate_tools = Keyword.get(opts, :validate_tools, true)
    validate_binaries = Keyword.get(opts, :validate_binaries, true)
    generate_manifest = Keyword.get(opts, :generate_manifest, true)
    generate_checksums = Keyword.get(opts, :generate_checksums, true)
    smoke_test_binaries = Keyword.get(opts, :smoke_test_binaries, true)
    smoke_test_opts = Keyword.get(opts, :smoke_test_opts, [])
    verify_upload = Keyword.get(opts, :verify_upload, false)
    verification_fetcher = Keyword.get(opts, :verification_fetcher)
    verification_timeout = Keyword.get(opts, :verification_timeout)
    verify_smoke_test = Keyword.get(opts, :verify_smoke_test, false)
    dry_run = Keyword.get(opts, :dry_run, false)
    overwrite_policy = Keyword.get(opts, :overwrite_policy, :overwrite)
    deployment_config = resolve_deployment_config(config_provider, destination)
    bucket = Keyword.get(opts, :bucket, Map.get(deployment_config, :bucket))

    prefix =
      Keyword.get(opts, :prefix, Map.get(deployment_config, :prefix, "tailwind_cli_daisyui"))

    storage_base_url =
      Keyword.get(
        opts,
        :storage_base_url,
        Application.get_env(:tailwind_builder, :storage_base_url, @default_storage_base_url)
      )

    maybe_put_runtime_config(opts[:storage], storage_base_url)
    File.mkdir_p!(source_path)

    with :ok <-
           allow_warning(
             config_provider.validate_operation_policy(:download, %{version: version})
           ),
         :ok <-
           allow_warning(config_provider.validate_operation_policy(:build, %{version: version})),
         :ok <-
           allow_warning(
             config_provider.validate_operation_policy(:deploy, %{target: destination})
           ),
         {:plugins, {:ok, resolved_plugins, plugin_set}} <-
           {:plugins, resolve_plugins(plugins, config_provider)},
         {:download, {:ok, download_result}} <-
           {:download, download_source(version, source_path, config_provider)},
         {:apply_plugins, {:ok, plugin_results}} <-
           {:apply_plugins, apply_plugins(resolved_plugins, version, source_path)},
         {:build, {:ok, build_result}} <-
           {:build,
            Builder.compile(
              version: version,
              source_path: source_path,
              debug: debug,
              validate_tools: validate_tools
            )},
         {:deploy, {:ok, deploy_result}} <-
           {:deploy,
            Deployer.deploy(
              version: version,
              source_path: source_path,
              destination: destination,
              bucket: bucket,
              prefix: prefix,
              release_channel: release_channel,
              plugin_set: plugin_set,
              storage_base_url: storage_base_url,
              validate_binaries: validate_binaries,
              generate_manifest: generate_manifest,
              generate_checksums: generate_checksums,
              smoke_test_binaries: smoke_test_binaries,
              smoke_test_opts: smoke_test_opts,
              verify_upload: verify_upload,
              verification_fetcher: verification_fetcher,
              verification_timeout: verification_timeout,
              verify_smoke_test: verify_smoke_test,
              dry_run: dry_run,
              overwrite_policy: overwrite_policy,
              tailwind_version: Keyword.get(opts, :tailwind_version, version),
              tailwind_cli_version: Keyword.get(opts, :tailwind_cli_version, version),
              source_checksum: Keyword.get(opts, :source_checksum),
              merge_manifest: Keyword.get(opts, :merge_manifest, true),
              compose_targets: Keyword.get(opts, :compose_targets)
            )} do
      {:ok,
       %{
         version: version,
         release_channel: release_channel,
         source_path: source_path,
         destination: destination,
         dry_run: dry_run,
         bucket: bucket,
         prefix: prefix,
         storage_base_url: storage_base_url,
         plugin_set: plugin_set,
         download: download_result,
         plugins: plugin_results,
         build: build_result,
         deploy: deploy_result
       }}
    else
      {:plugins, {:error, reason}} ->
        {:error, {:plugins, reason}}

      {:download, {:error, reason}} ->
        {:error, {:download, reason}}

      {:apply_plugins, {:error, reason}} ->
        {:error, {:apply_plugins, reason}}

      {:build, {:error, reason}} ->
        {:error, {:build, reason}}

      {:deploy, {:error, reason}} ->
        {:error, {:deploy, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Run the pinned Tailwind 4.2.2 release candidate flow.
  """
  def tailwind_4_2_2_rc1(opts \\ []) do
    run(
      Keyword.merge(
        [
          version: @default_version,
          release_channel: @default_release_channel,
          plugins: @default_plugins
        ],
        opts
      )
    )
  end

  defp default_source_path(release_channel) do
    Path.join(System.tmp_dir!(), "tailwind_builder_#{release_channel}")
  end

  defp allow_warning(:ok), do: :ok
  defp allow_warning({:warning, _message}), do: :ok
  defp allow_warning(other), do: other

  defp download_source(version, source_path, config_provider) do
    expected_checksum =
      config_provider.get_known_checksums()
      |> Map.get(version)

    Downloader.download_and_extract(
      version: version,
      destination: source_path,
      expected_checksum: expected_checksum
    )
  end

  defp resolve_plugins(plugin_inputs, config_provider) do
    supported_plugins = config_provider.get_supported_plugins()

    resolved_plugins =
      Enum.map(plugin_inputs, fn
        plugin_name when is_binary(plugin_name) ->
          case Map.get(supported_plugins, plugin_name) do
            nil ->
              {:error, {:unsupported_plugin, plugin_name}}

            spec ->
              {:ok,
               %{
                 plugin_name: plugin_name,
                 spec: spec,
                 manifest: manifest_plugin_entry(plugin_name, spec)
               }}
          end

        %{"version" => _version} = spec ->
          name = PluginManager.extract_plugin_name(spec)

          {:ok,
           %{
             plugin_name: name,
             spec: spec,
             manifest: manifest_plugin_entry(name, spec)
           }}

        other ->
          {:error, {:invalid_plugin_input, other}}
      end)

    case Enum.find(resolved_plugins, &match?({:error, _}, &1)) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        plugins = Enum.map(resolved_plugins, fn {:ok, plugin} -> plugin end)
        {:ok, plugins, Enum.map(plugins, & &1.manifest)}
    end
  end

  defp apply_plugins(resolved_plugins, version, source_path) do
    results =
      Enum.map(resolved_plugins, fn plugin ->
        PluginManager.apply_plugin(
          plugin.spec,
          version: version,
          base_path: source_path,
          plugin_name: plugin.plugin_name
        )
      end)

    failures =
      Enum.filter(results, fn
        {:error, _reason} -> true
        _ -> false
      end)

    case failures do
      [] -> {:ok, results}
      _ -> {:error, {:plugin_failures, failures}}
    end
  end

  defp manifest_plugin_entry(plugin_name, %{"version" => version_spec}) do
    case Regex.run(~r/"([^"]+)"\s*:\s*"([^"]+)"/, version_spec) do
      [_, package_name, version] ->
        %{name: package_name, version: version, plugin_key: plugin_name}

      _ ->
        %{name: plugin_name, version: version_spec, plugin_key: plugin_name}
    end
  end

  defp maybe_put_runtime_config(nil, storage_base_url) do
    Application.put_env(:tailwind_builder, :storage_base_url, storage_base_url)
  end

  defp maybe_put_runtime_config(storage_config, storage_base_url) when is_map(storage_config) do
    normalized =
      storage_config
      |> Map.to_list()
      |> Enum.map(fn
        {:host, host} -> {:host, Deployer.normalize_storage_host(host)}
        other -> other
      end)

    Application.put_env(:tailwind_builder, :storage, normalized)
    Application.put_env(:tailwind_builder, :storage_base_url, storage_base_url)
  end

  defp resolve_deployment_config(config_provider, destination) do
    config_provider.get_deployment_config(destination)
  rescue
    CaseClauseError ->
      Logger.warning(
        "Config provider #{inspect(config_provider)} does not define deployment config for #{inspect(destination)}, falling back to explicit release options"
      )

      %{}

    FunctionClauseError ->
      Logger.warning(
        "Config provider #{inspect(config_provider)} does not support deployment config lookup for #{inspect(destination)}, falling back to explicit release options"
      )

      %{}
  end
end
