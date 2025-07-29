defmodule Defdo.TailwindBuilderIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Defdo.TailwindBuilder.{
    Core,
    Downloader,
    PluginManager,
    Builder,
    Deployer,
    DefaultConfigProvider,
    Orchestrator
  }

  @moduletag :integration
  @moduletag :capture_log

  # Test data
  @test_version "3.4.17"
  @test_plugin_spec %{
    "version" => ~s["daisyui": "^4.12.23"],
    "statement" => ~s['daisyui': require('daisyui')]
  }

  setup do
    # Create a unique temporary directory for each test
    test_id = System.unique_integer([:positive])
    temp_dir = "/tmp/tailwind_integration_test_#{test_id}"
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    %{temp_dir: temp_dir}
  end

  describe "Full pipeline integration tests" do
    @tag :full_pipeline
    test "complete download -> plugin -> build -> deploy flow", %{temp_dir: temp_dir} do
      # Step 1: Download
      assert {:ok, download_result} = Downloader.download_and_extract([
        version: @test_version,
        destination: temp_dir,
        expected_checksum: DefaultConfigProvider.get_known_checksums()[@test_version]
      ])

      assert download_result.extracted_path =~ @test_version
      assert File.exists?(download_result.extracted_path)

      # Step 2: Apply Plugin
      assert {:ok, plugin_result} = PluginManager.apply_plugin(@test_plugin_spec, [
        version: @test_version,
        base_path: temp_dir,
        validate_compatibility: false  # Skip for integration test
      ])

      assert plugin_result.plugin == "daisyui"
      assert plugin_result.files_patched > 0

      # Step 3: Build (mock for integration test)
      assert {:ok, build_paths} = Builder.get_build_paths(temp_dir, @test_version)
      assert build_paths.tailwind_root =~ @test_version
      assert build_paths.standalone_root =~ @test_version

      # Step 4: Create mock binaries for deployment test
      dist_dir = Path.join(build_paths.standalone_root, "dist")
      File.mkdir_p!(dist_dir)

      # Create mock binary files with sufficient size
      mock_binary_content = String.duplicate("mock binary content", 1000)
      File.write!(Path.join(dist_dir, "tailwindcss-linux-x64"), mock_binary_content)
      File.write!(Path.join(dist_dir, "tailwindcss-macos-arm64"), mock_binary_content)

      # Step 5: Find and validate binaries
      assert {:ok, binaries} = Deployer.find_distributable_binaries(temp_dir, @test_version)
      assert length(binaries) == 2

      # Verify binary info structure
      binary = hd(binaries)
      assert binary.filename in ["tailwindcss-linux-x64", "tailwindcss-macos-arm64"]
      assert binary.size > 1000
      assert File.exists?(binary.path)

      # Step 6: Generate deployment manifest
      assert {:ok, manifest} = Deployer.generate_deployment_manifest(binaries, @test_version)
      assert manifest.version == @test_version
      assert manifest.compilation_method in [:npm, :pnpm, :rust]
      assert is_binary(manifest.timestamp)
    end

    @tag :orchestrator_integration
    test "orchestrator coordinates all modules correctly", %{temp_dir: temp_dir} do
      # Test the orchestrator's ability to coordinate the full workflow
      workflow_config = [
        version: @test_version,
        source_path: temp_dir,
        plugins: [@test_plugin_spec],
        validate_checksums: true,
        build: false,  # Skip actual build for integration test
        deploy: false, # Skip actual deploy for integration test
        config_provider: DefaultConfigProvider
      ]

      assert {:ok, workflow_result} = Orchestrator.execute_workflow(workflow_config)

      # Verify each step was executed
      assert workflow_result.download_completed
      assert workflow_result.plugins_applied > 0
      assert workflow_result.version == @test_version

      # Verify files were created and modified
      extracted_path = Path.join([temp_dir, "tailwindcss-#{@test_version}"])
      assert File.exists?(extracted_path)
    end
  end

  describe "Module interaction tests" do
    @tag :downloader_plugin_integration
    test "downloader and plugin manager integration", %{temp_dir: temp_dir} do
      # Test that downloaded files can be immediately used by plugin manager

      # Download first
      assert {:ok, _download_result} = Downloader.download_and_extract([
        version: @test_version,
        destination: temp_dir,
        expected_checksum: DefaultConfigProvider.get_known_checksums()[@test_version]
      ])

      # Immediately apply plugin to downloaded files
      assert {:ok, plugin_result} = PluginManager.apply_plugin(@test_plugin_spec, [
        version: @test_version,
        base_path: temp_dir,
        validate_compatibility: false
      ])

      # Verify plugin was applied to correct files
      assert plugin_result.files_patched >= 1

      # Verify the actual files were modified
      standalone_path = case Version.compare(@test_version, "4.0.0") do
        :lt -> Path.join([temp_dir, "tailwindcss-#{@test_version}", "standalone-cli", "package.json"])
        _ -> Path.join([temp_dir, "tailwindcss-#{@test_version}", "packages", "@tailwindcss-standalone", "package.json"])
      end

      if File.exists?(standalone_path) do
        content = File.read!(standalone_path)
        assert content =~ "daisyui"
      end
    end

    @tag :builder_deployer_integration
    test "builder and deployer integration", %{temp_dir: temp_dir} do
      # Test that builder paths work correctly with deployer

      # Get build paths from builder
      assert {:ok, build_paths} = Builder.get_build_paths(temp_dir, @test_version)

      # Create the directory structure that builder would create
      File.mkdir_p!(build_paths.standalone_root)
      dist_dir = Path.join(build_paths.standalone_root, "dist")
      File.mkdir_p!(dist_dir)

      # Create mock binaries
      mock_content = String.duplicate("binary data", 2000)
      File.write!(Path.join(dist_dir, "tailwindcss-linux-x64"), mock_content)
      File.chmod!(Path.join(dist_dir, "tailwindcss-linux-x64"), 0o755)

      # Test that deployer can find and process these binaries
      assert {:ok, binaries} = Deployer.find_distributable_binaries(temp_dir, @test_version)
      assert length(binaries) >= 1

      binary = hd(binaries)
      assert binary.path =~ dist_dir
      assert binary.filename == "tailwindcss-linux-x64"
    end

    @tag :config_provider_integration
    test "config provider integration with all modules", %{temp_dir: temp_dir} do
      # Test that config provider settings affect all modules correctly

      config = DefaultConfigProvider

      # Test with VersionFetcher
      checksums = config.get_known_checksums()
      assert is_map(checksums)
      assert Map.has_key?(checksums, @test_version)

      # Test with Downloader using config
      assert {:ok, _} = Downloader.download_and_extract([
        version: @test_version,
        destination: temp_dir,
        expected_checksum: checksums[@test_version]
      ])

      # Test config validation
      assert :ok = config.validate_operation_policy(@test_version, :download)
      assert :ok = config.validate_operation_policy(@test_version, :build)
      assert :ok = config.validate_operation_policy(@test_version, :deploy)
    end
  end

  describe "Error handling integration" do
    @tag :error_propagation
    test "errors propagate correctly through the pipeline", %{temp_dir: temp_dir} do
      # Test with invalid version
      invalid_version = "99.99.99"

      # This should fail at download step
      assert {:error, _} = Downloader.download_and_extract([
        version: invalid_version,
        destination: temp_dir
      ])

      # Test with missing files for plugin manager
      assert {:error, _} = PluginManager.apply_plugin(@test_plugin_spec, [
        version: invalid_version,
        base_path: "/nonexistent/path"
      ])

      # Test with missing source for deployer
      assert {:error, _} = Deployer.find_distributable_binaries("/nonexistent", invalid_version)
    end

    @tag :partial_failure_recovery
    test "system handles partial failures gracefully", %{temp_dir: temp_dir} do
      # Download successfully
      assert {:ok, _} = Downloader.download_and_extract([
        version: @test_version,
        destination: temp_dir,
        expected_checksum: DefaultConfigProvider.get_known_checksums()[@test_version]
      ])

      # Try to apply an invalid plugin (should fail gracefully)
      invalid_plugin = %{"invalid" => "spec"}

      assert {:error, {step, _error}} = PluginManager.apply_plugin(invalid_plugin, [
        version: @test_version,
        base_path: temp_dir
      ])

      assert step == :validate_spec

      # But the downloaded files should still be intact
      extracted_path = Path.join([temp_dir, "tailwindcss-#{@test_version}"])
      assert File.exists?(extracted_path)
    end
  end

  describe "Performance integration tests" do
    @tag :performance
    @tag timeout: 30_000
    test "full pipeline completes within reasonable time", %{temp_dir: temp_dir} do
      start_time = System.monotonic_time(:millisecond)

      # Execute a complete workflow
      assert {:ok, _} = Orchestrator.execute_workflow([
        version: @test_version,
        source_path: temp_dir,
        plugins: [@test_plugin_spec],
        build: false,  # Skip build for performance test
        deploy: false, # Skip deploy for performance test
        config_provider: DefaultConfigProvider
      ])

      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time

      # Should complete within 15 seconds (excluding actual build/deploy)
      assert execution_time < 15_000, "Pipeline took #{execution_time}ms, expected < 15000ms"
    end

    @tag :concurrent_operations
    test "modules handle concurrent operations safely", %{temp_dir: temp_dir} do
      # Test concurrent downloads to different destinations
      tasks = for i <- 1..3 do
        dest_dir = Path.join(temp_dir, "concurrent_#{i}")
        File.mkdir_p!(dest_dir)

        Task.async(fn ->
          Downloader.download_and_extract([
            version: @test_version,
            destination: dest_dir,
            expected_checksum: DefaultConfigProvider.get_known_checksums()[@test_version]
          ])
        end)
      end

      results = Task.await_many(tasks, 30_000)

      # All downloads should succeed
      for result <- results do
        assert {:ok, _} = result
      end

      # Verify all extractions completed
      for i <- 1..3 do
        extracted_path = Path.join([temp_dir, "concurrent_#{i}", "tailwindcss-#{@test_version}"])
        assert File.exists?(extracted_path)
      end
    end
  end

  describe "Cross-version compatibility tests" do
    @tag :version_compatibility
    test "modules work correctly across different Tailwind versions" do
      versions_to_test = ["3.4.17", "4.0.9", "4.1.11"]

      for version <- versions_to_test do
        temp_dir = "/tmp/version_test_#{version}_#{System.unique_integer()}"
        File.mkdir_p!(temp_dir)

        try do
          # Test that each module can handle the version
          constraints = Core.get_version_constraints(version)
          assert constraints.major_version in [:v3, :v4]

          # Test config provider knows about the version
          config = DefaultConfigProvider
          checksums = config.get_known_checksums()

          if Map.has_key?(checksums, version) do
            # Test download if we have checksum
            assert {:ok, _} = Downloader.download_and_extract([
              version: version,
              destination: temp_dir,
              expected_checksum: checksums[version]
            ])
          end

          # Test plugin compatibility detection
          compatibility = PluginManager.get_plugin_compatibility(@test_plugin_spec, version)
          assert compatibility.version == version
          assert is_boolean(compatibility.is_compatible)

        after
          File.rm_rf!(temp_dir)
        end
      end
    end
  end

  describe "Real-world scenario tests" do
    @tag :real_world
    @tag timeout: 60_000
    test "developer workflow: download, customize, build-prep", %{temp_dir: temp_dir} do
      # Simulate a typical developer workflow

      # 1. Developer downloads Tailwind
      capture_log(fn ->
        assert {:ok, _download_result} = Downloader.download_and_extract([
          version: @test_version,
          destination: temp_dir,
          expected_checksum: DefaultConfigProvider.get_known_checksums()[@test_version]
        ])

        assert File.exists?(_download_result.extracted_path)
      end)

      # 2. Developer adds multiple plugins
      plugins = [
        @test_plugin_spec,
        %{
          "version" => ~s["@tailwindcss/typography": "^0.5.0"],
          "statement" => ~s['@tailwindcss/typography': require('@tailwindcss/typography')]
        }
      ]

      applied_plugins = for plugin <- plugins do
        case PluginManager.apply_plugin(plugin, [
          version: @test_version,
          base_path: temp_dir,
          validate_compatibility: false
        ]) do
          {:ok, result} -> result
          {:error, _} -> nil  # Some plugins might not be compatible
        end
      end

      successful_plugins = Enum.filter(applied_plugins, & &1)
      assert length(successful_plugins) >= 1

      # 3. Developer prepares for build
      assert {:ok, build_paths} = Builder.get_build_paths(temp_dir, @test_version)
      assert File.exists?(build_paths.tailwind_root)

      # 4. Developer checks what would be deployed
      # Create mock dist directory as if build completed
      dist_dir = Path.join(build_paths.standalone_root, "dist")
      File.mkdir_p!(dist_dir)

      mock_binaries = ["tailwindcss-linux-x64", "tailwindcss-macos-arm64", "tailwindcss-win32-x64"]
      for binary_name <- mock_binaries do
        File.write!(Path.join(dist_dir, binary_name), "mock binary content for #{binary_name}")
      end

      assert {:ok, binaries} = Deployer.find_distributable_binaries(temp_dir, @test_version)
      assert length(binaries) == length(mock_binaries)

      # 5. Generate deployment manifest
      assert {:ok, manifest} = Deployer.generate_deployment_manifest(binaries, @test_version)
      assert manifest.version == @test_version
      assert length(manifest.files) == length(mock_binaries)
    end

    @tag :ci_cd_simulation
    test "CI/CD pipeline simulation", %{temp_dir: temp_dir} do
      # Simulate a CI/CD environment workflow

      # CI Step 1: Download and validate
      config = DefaultConfigProvider

      assert {:ok, _download_result} = Downloader.download_and_extract([
        version: @test_version,
        destination: temp_dir,
        expected_checksum: config.get_known_checksums()[@test_version]
      ])

      # CI Step 2: Apply required plugins (from config)
      required_plugins = [
        %{
          "version" => ~s["daisyui": "^4.12.23"],
          "statement" => ~s['daisyui': require('daisyui')]
        }
      ]

      plugin_results = for plugin <- required_plugins do
        PluginManager.apply_plugin(plugin, [
          version: @test_version,
          base_path: temp_dir,
          validate_compatibility: true
        ])
      end

      # Verify all plugins applied successfully
      for result <- plugin_results do
        assert {:ok, _} = result
      end

      # CI Step 3: Validate configuration
      assert {:ok, build_paths} = Builder.get_build_paths(temp_dir, @test_version)
      assert File.exists?(build_paths.tailwind_root)

      # CI Step 4: Prepare deployment artifacts (simulate)
      dist_dir = Path.join(build_paths.standalone_root, "dist")
      File.mkdir_p!(dist_dir)

      # Create artifacts
      targets = ["linux-x64", "macos-arm64", "win32-x64"]
      for target <- targets do
        binary_name = "tailwindcss-#{target}"
        File.write!(Path.join(dist_dir, binary_name), "CI binary for #{target}")
      end

      assert {:ok, binaries} = Deployer.find_distributable_binaries(temp_dir, @test_version)
      assert length(binaries) == length(targets)

      # CI Step 5: Generate and validate manifest
      assert {:ok, manifest} = Deployer.generate_deployment_manifest(binaries, @test_version, format: :json)

      # Validate manifest structure
      manifest_data = Jason.decode!(manifest)
      assert manifest_data["version"] == @test_version
      assert is_list(manifest_data["files"])
      assert length(manifest_data["files"]) == length(targets)
    end
  end
end
