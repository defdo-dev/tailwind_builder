defmodule Defdo.TailwindBuilder.ReleaseTest do
  use ExUnit.Case, async: false

  import Mock

  alias Defdo.TailwindBuilder.Release
  alias Defdo.TailwindBuilder.ConfigProviders.{ProductionConfigProvider, TestingConfigProvider}

  defp temp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  setup do
    original_storage_base_url = Application.get_env(:tailwind_builder, :storage_base_url)
    original_storage = Application.get_env(:tailwind_builder, :storage)

    # Fake storage config so run/1's pre-deploy credential check passes for the
    # r2 happy-path tests (deploy itself is mocked). Error-path tests fail at
    # plugin/policy validation before this is consulted.
    Application.put_env(:tailwind_builder, :storage,
      access_key_id: "test-key",
      secret_access_key: "test-secret",
      host: "test.r2.cloudflarestorage.com",
      region: "auto"
    )

    on_exit(fn ->
      restore_env(:storage_base_url, original_storage_base_url)
      restore_env(:storage, original_storage)
    end)

    :ok
  end

  describe "run/1" do
    test "orchestrates download, plugin application, build, and deploy for Tailwind 4.2.2" do
      parent = self()
      source_path = temp_dir("release_flow")

      on_exit(fn -> File.rm_rf(source_path) end)

      with_mocks([
        {Defdo.TailwindBuilder.Downloader, [],
         [
           download_and_extract: fn opts ->
             send(parent, {:download_opts, opts})

             {:ok,
              %{
                version: opts[:version],
                destination: opts[:destination],
                extracted_path: Path.join(opts[:destination], "tailwindcss-#{opts[:version]}")
              }}
           end
         ]},
        {Defdo.TailwindBuilder.PluginManager, [],
         [
           apply_plugin: fn plugin_spec, opts ->
             send(parent, {:plugin_opts, plugin_spec, opts})
             {:ok, %{plugin: "daisyui", version: opts[:version], files_patched: 2}}
           end
         ]},
        {Defdo.TailwindBuilder.Builder, [],
         [
           compile: fn opts ->
             send(parent, {:build_opts, opts})

             {:ok,
              %{
                version: opts[:version],
                source_path: opts[:source_path],
                standalone_root: Path.join(opts[:source_path], "dist")
              }}
           end
         ]},
        {Defdo.TailwindBuilder.Deployer, [],
         [
           deploy: fn opts ->
             send(parent, {:deploy_opts, opts})

             {:ok,
              %{
                binaries_deployed: 3,
                manifest: %{version: opts[:version], release_channel: opts[:release_channel]},
                sha256sums: "abc123  tailwindcss-linux-x64"
              }}
           end
         ]}
      ]) do
        assert {:ok, result} =
                 Release.run(
                   version: "4.2.2",
                   release_channel: "v4.2.2-rc1",
                   source_path: source_path,
                   config_provider: TestingConfigProvider,
                   destination: :r2,
                   bucket: "defdo",
                   prefix: "tailwind_cli_daisyui",
                   storage_base_url: "https://storage.defdo.de",
                   plugins: ["daisyui_v5"]
                 )

        assert result.version == "4.2.2"
        assert result.release_channel == "v4.2.2-rc1"

        assert result.plugin_set == [
                 %{name: "daisyui", version: "5.5.19", plugin_key: "daisyui_v5"}
               ]

        assert result.deploy.binaries_deployed == 3

        assert_received {:download_opts, download_opts}

        assert download_opts[:expected_checksum] ==
                 "b8ff36e8115f56883638d593563418ee279be9f8304107add89f79d9cbf5b147"

        assert_received {:plugin_opts, plugin_spec, plugin_opts}
        assert plugin_spec["version"] == ~s["daisyui": "5.5.19"]
        assert plugin_opts[:base_path] == source_path
        assert plugin_opts[:version] == "4.2.2"

        assert_received {:build_opts, build_opts}
        assert build_opts[:source_path] == source_path
        assert build_opts[:version] == "4.2.2"
        assert build_opts[:validate_tools] == true

        assert_received {:deploy_opts, deploy_opts}
        assert deploy_opts[:bucket] == "defdo"
        assert deploy_opts[:prefix] == "tailwind_cli_daisyui"
        assert deploy_opts[:release_channel] == "v4.2.2-rc1"
        assert deploy_opts[:storage_base_url] == "https://storage.defdo.de"
        assert deploy_opts[:plugin_set] == result.plugin_set
      end
    end

    test "forwards verify_upload and verification options to the deployer" do
      parent = self()
      source_path = temp_dir("release_verify")
      on_exit(fn -> File.rm_rf(source_path) end)

      fetcher = fn _url -> {:ok, "bytes"} end

      with_mocks([
        {Defdo.TailwindBuilder.Downloader, [],
         [
           download_and_extract: fn opts ->
             {:ok,
              %{
                version: opts[:version],
                destination: opts[:destination],
                extracted_path: Path.join(opts[:destination], "tailwindcss-#{opts[:version]}")
              }}
           end
         ]},
        {Defdo.TailwindBuilder.PluginManager, [],
         [
           apply_plugin: fn _plugin_spec, opts ->
             {:ok, %{plugin: "daisyui", version: opts[:version], files_patched: 2}}
           end
         ]},
        {Defdo.TailwindBuilder.Builder, [],
         [
           compile: fn opts ->
             {:ok,
              %{
                version: opts[:version],
                source_path: opts[:source_path],
                standalone_root: Path.join(opts[:source_path], "dist")
              }}
           end
         ]},
        {Defdo.TailwindBuilder.Deployer, [],
         [
           deploy: fn opts ->
             send(parent, {:deploy_opts, opts})
             {:ok, %{binaries_deployed: 1, manifest: %{}, sha256sums: "abc"}}
           end
         ]}
      ]) do
        assert {:ok, _result} =
                 Release.run(
                   version: "4.2.2",
                   release_channel: "v4.2.2-rc1",
                   source_path: source_path,
                   config_provider: TestingConfigProvider,
                   destination: :r2,
                   bucket: "defdo",
                   prefix: "tailwind_cli_daisyui",
                   storage_base_url: "https://storage.defdo.de",
                   plugins: ["daisyui_v5"],
                   verify_upload: true,
                   verification_fetcher: fetcher,
                   verification_timeout: 5_000
                 )

        assert_received {:deploy_opts, deploy_opts}
        assert deploy_opts[:verify_upload] == true
        assert deploy_opts[:verification_fetcher] == fetcher
        assert deploy_opts[:verification_timeout] == 5_000
      end
    end

    test "returns plugin errors before downloading when a plugin is unsupported" do
      source_path = temp_dir("release_plugin_error")
      on_exit(fn -> File.rm_rf(source_path) end)

      assert {:error, {:plugins, {:unsupported_plugin, "missing_plugin"}}} =
               Release.run(
                 version: "4.2.2",
                 source_path: source_path,
                 config_provider: TestingConfigProvider,
                 plugins: ["missing_plugin"]
               )
    end

    test "returns provider policy errors for blocked versions" do
      source_path = temp_dir("release_policy_error")
      on_exit(fn -> File.rm_rf(source_path) end)

      assert {:error, {:version_blocked, "Version 4.0.9 is not allowed in production"}} =
               Release.run(
                 version: "4.0.9",
                 source_path: source_path,
                 config_provider: ProductionConfigProvider,
                 destination: :r2
               )
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:tailwind_builder, key)
  defp restore_env(key, value), do: Application.put_env(:tailwind_builder, key, value)
end
