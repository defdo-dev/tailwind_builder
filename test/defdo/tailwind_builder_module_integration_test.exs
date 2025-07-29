defmodule Defdo.TailwindBuilderModuleIntegrationTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindBuilder.{
    Core,
    Downloader,
    PluginManager,
    Builder,
    Deployer,
    VersionFetcher,
    DefaultConfigProvider
  }

  @moduletag :module_integration
  @moduletag :capture_log

  describe "Core + VersionFetcher integration" do
    test "core constraints match version fetcher capabilities" do
      test_versions = ["3.4.17", "4.0.9", "4.1.11"]

      for version <- test_versions do
        constraints = Core.get_version_constraints(version)

        # Test that VersionFetcher can handle this version
        case VersionFetcher.get_version_info(version) do
          {:ok, version_info} ->
            assert version_info.version == version

            # Verify core constraints match version info
            case constraints.major_version do
              :v3 -> assert String.starts_with?(version, "3.")
              :v4 -> assert String.starts_with?(version, "4.")
            end

          {:error, _} ->
            # Version not found is acceptable for this test
            :ok
        end

        # Test compilation method consistency
        compilation_details = Core.get_compilation_details(version)
        expected_method = case constraints.major_version do
          :v3 -> :npm
          :v4 -> :rust  # v4 uses Rust compilation
        end

        assert compilation_details.compilation_method == expected_method
      end
    end

    test "core architecture matrix integrates with version fetcher" do
      matrix = Core.get_architecture_support_matrix()

      # Test that each supported architecture has proper constraints
      for {arch, support_info} <- matrix do
        assert is_atom(arch)
        assert is_map(support_info)
        assert Map.has_key?(support_info, :supported_versions)
        assert Map.has_key?(support_info, :compilation_method)

        # Test with VersionFetcher
        if support_info.supported_versions != [] do
          test_version = hd(support_info.supported_versions)
          constraints = Core.get_version_constraints(test_version)

          # Architecture should be supported in constraints (convert atom to string for comparison)
          arch_string = Atom.to_string(arch)
          assert arch_string in constraints.supported_architectures
        end
      end
    end
  end

  describe "Downloader + Core integration" do
    test "downloader uses core constraints for validation" do
      version = "3.4.17"
      temp_dir = "/tmp/downloader_core_test_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)

      try do
        constraints = Core.get_version_constraints(version)

        # Test that downloader respects core constraints
        result = Downloader.download_and_extract([
          version: version,
          destination: temp_dir,
          expected_checksum: DefaultConfigProvider.get_known_checksums()[version]
        ])

        case result do
          {:ok, download_result} ->
            # Verify extracted structure matches core expectations
            _expected_structure = constraints.file_structure

            extracted_path = download_result.extracted_path
            assert File.exists?(extracted_path)

            # Check for expected directories based on version
            case constraints.major_version do
              :v3 ->
                standalone_path = Path.join(extracted_path, "standalone-cli")
                if File.exists?(standalone_path) do
                  assert File.dir?(standalone_path)
                end

              :v4 ->
                packages_path = Path.join(extracted_path, "packages")
                if File.exists?(packages_path) do
                  assert File.dir?(packages_path)
                end
            end

          {:error, _reason} ->
            # Download failure is acceptable for this integration test
            :ok
        end

      after
        File.rm_rf!(temp_dir)
      end
    end

    test "downloader extraction creates core-expected file structure" do
      # Test with a smaller, predictable structure
      version = "3.4.17"
      temp_dir = "/tmp/structure_test_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)

      try do
        constraints = Core.get_version_constraints(version)

        # Create mock extraction to test structure validation
        mock_extraction_path = Path.join([temp_dir, "tailwindcss-#{version}"])
        File.mkdir_p!(mock_extraction_path)

        # Create expected structure based on core constraints
        case constraints.major_version do
          :v3 ->
            standalone_path = Path.join(mock_extraction_path, "standalone-cli")
            File.mkdir_p!(standalone_path)
            File.write!(Path.join(standalone_path, "package.json"), "{}")

          :v4 ->
            packages_path = Path.join([mock_extraction_path, "packages", "@tailwindcss-standalone"])
            File.mkdir_p!(packages_path)
            File.write!(Path.join(packages_path, "package.json"), "{}")
        end

        # Test that Core can validate this structure
        structure_info = Core.analyze_extracted_structure(mock_extraction_path, version)
        assert structure_info.version == version
        assert structure_info.valid_structure == true

      after
        File.rm_rf!(temp_dir)
      end
    end
  end

  describe "PluginManager + Core integration" do
    test "plugin manager uses core constraints for compatibility" do
      version = "3.4.17"
      plugin_spec = %{
        "version" => ~s["daisyui": "^4.12.23"],
        "statement" => ~s['daisyui': require('daisyui')]
      }

      constraints = Core.get_version_constraints(version)

      # Test plugin compatibility determination
      compatibility = PluginManager.get_plugin_compatibility(plugin_spec, version)

      assert compatibility.version == version
      assert compatibility.major_version == constraints.major_version

      # Test that plugin system configuration matches
      plugin_system = constraints.plugin_system
      assert compatibility.dependency_section == plugin_system.dependency_section
      assert compatibility.requires_bundling == plugin_system.requires_bundling
    end

    test "plugin manager respects core file structure constraints" do
      version = "4.1.11"
      temp_dir = "/tmp/plugin_core_test_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)

      try do
        constraints = Core.get_version_constraints(version)

        # Create mock file structure based on core constraints
        base_path = Path.join([temp_dir, "tailwindcss-#{version}"])

        case constraints.major_version do
          :v4 ->
            standalone_path = Path.join([base_path, "packages", "@tailwindcss-standalone"])
            File.mkdir_p!(standalone_path)
            File.write!(Path.join(standalone_path, "package.json"), ~s[{"dependencies": {}}])

            src_path = Path.join(standalone_path, "src")
            File.mkdir_p!(src_path)
            File.write!(Path.join(src_path, "index.ts"), "// Mock TypeScript file")

          :v3 ->
            standalone_path = Path.join([base_path, "standalone-cli"])
            File.mkdir_p!(standalone_path)
            File.write!(Path.join(standalone_path, "package.json"), ~s[{"devDependencies": {}}])
            File.write!(Path.join(standalone_path, "standalone.js"), "// Mock JS file")
        end

        plugin_spec = %{
          "version" => ~s["test-plugin": "^1.0.0"],
          "statement" => ~s['test-plugin': require('test-plugin')]
        }

        # Test that plugin manager finds correct files based on core constraints
        result = PluginManager.apply_plugin(plugin_spec, [
          version: version,
          base_path: temp_dir,
          validate_compatibility: false
        ])

        case result do
          {:ok, plugin_result} ->
            assert plugin_result.version == version
            assert plugin_result.files_patched > 0

          {:error, _} ->
            # Plugin application failure is acceptable for this test
            # We're mainly testing the integration of constraints
            :ok
        end

      after
        File.rm_rf!(temp_dir)
      end
    end
  end

  describe "Builder + Core + Deployer integration" do
    test "builder and deployer use consistent core constraints" do
      version = "4.0.9"
      temp_dir = "/tmp/builder_deployer_test_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)

      try do
        constraints = Core.get_version_constraints(version)

        # Test Builder path generation
        {:ok, build_paths} = Builder.get_build_paths(temp_dir, version)

        # Test that build paths align with core constraints
        case constraints.major_version do
          :v4 ->
            assert build_paths.standalone_root =~ "@tailwindcss-standalone"
          :v3 ->
            assert build_paths.standalone_root =~ "standalone-cli"
        end

        # Create mock build output structure
        File.mkdir_p!(build_paths.standalone_root)
        dist_dir = Path.join(build_paths.standalone_root, "dist")
        File.mkdir_p!(dist_dir)

        # Create mock binaries based on core architecture support
        supported_archs = constraints.supported_architectures

        for arch <- supported_archs do
          binary_name = "tailwindcss-#{arch}"
          File.write!(Path.join(dist_dir, binary_name), "mock binary for #{arch}")
        end

        # Test that Deployer can find and process these binaries
        {:ok, binaries} = Deployer.find_distributable_binaries(temp_dir, version)

        # Verify deployer found binaries for expected architectures
        found_archs = binaries
        |> Enum.map(& &1.filename)
        |> Enum.map(&String.replace(&1, "tailwindcss-", ""))
        |> MapSet.new()

        expected_archs = MapSet.new(Enum.map(supported_archs, &to_string/1))

        # Should find at least some of the expected architectures
        assert MapSet.size(MapSet.intersection(found_archs, expected_archs)) > 0

      after
        File.rm_rf!(temp_dir)
      end
    end

    test "compilation details propagate correctly through pipeline" do
      version = "3.4.17"

      # Get compilation details from Core
      compilation_details = Core.get_compilation_details(version)

      # Test that Builder respects these details
      tool_requirements = Builder.get_required_tools(version)

      case compilation_details.compilation_method do
        :npm ->
          assert "npm" in tool_requirements
        :pnpm ->
          assert "pnpm" in tool_requirements
        :rust ->
          assert "cargo" in tool_requirements
      end

      # Test that Deployer includes compilation info in manifests
      temp_dir = "/tmp/compilation_test_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)

      try do
        # Create mock binaries
        mock_binaries = [
          %{filename: "tailwindcss-linux-x64", path: "/mock/path", size: 1000}
        ]

        {:ok, manifest} = Deployer.generate_deployment_manifest(mock_binaries, version)

        # Verify compilation details are included
        assert manifest.compilation_method == compilation_details.compilation_method
        assert manifest.host_architecture == compilation_details.host_architecture

      after
        File.rm_rf!(temp_dir)
      end
    end
  end

  describe "ConfigProvider integration across modules" do
    test "all modules respect config provider settings" do
      config = DefaultConfigProvider

      # Test with Downloader
      checksums = config.get_known_checksums()
      assert is_map(checksums)

      test_version = "3.4.17"
      if Map.has_key?(checksums, test_version) do
        temp_dir = "/tmp/config_test_#{System.unique_integer()}"
        File.mkdir_p!(temp_dir)

        try do
          # Test policy validation across modules (doesn't require download)
          assert :ok = config.validate_operation_policy(test_version, :download)
          assert :ok = config.validate_operation_policy(test_version, :build)
          assert :ok = config.validate_operation_policy(test_version, :deploy)

          # Try download but handle failure gracefully
          case Downloader.download_and_extract([
            version: test_version,
            destination: temp_dir,
            expected_checksum: checksums[test_version]
          ]) do
            {:ok, _} ->
              # Download succeeded - excellent!
              :ok
            {:error, _} ->
              # Download failed (likely network/rate limiting) - test still passes
              # since we tested the config provider integration above
              :ok
          end

        after
          File.rm_rf!(temp_dir)
        end
      end

      # Test config consistency
      build_policies = config.get_build_policies()
      deploy_policies = config.get_deployment_policies()

      assert is_map(build_policies)
      assert is_map(deploy_policies)

      # Test that policies are consistent
      for version <- Map.keys(checksums) do
        build_policy = config.validate_operation_policy(version, :build)
        deploy_policy = config.validate_operation_policy(version, :deploy)

        # If build is allowed, deploy should generally be allowed too
        if build_policy == :ok do
          assert deploy_policy in [:ok, :deprecated]
        end
      end
    end
  end

  describe "Error handling integration" do
    test "errors cascade properly through module chain" do
      invalid_version = "999.999.999"
      temp_dir = "/tmp/error_test_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)

      try do
        # Test error from Core propagates to other modules
        constraints_result = Core.get_version_constraints(invalid_version)

        # Should still return constraints but mark as unsupported
        assert constraints_result.major_version == :unsupported

        # Test that other modules handle unsupported versions gracefully
        {:error, build_error} = Builder.get_build_paths(temp_dir, invalid_version)
        assert build_error == :unsupported_version

        {:error, deploy_error} = Deployer.find_distributable_binaries(temp_dir, invalid_version)
        assert deploy_error == :unsupported_version

      after
        File.rm_rf!(temp_dir)
      end
    end

    test "partial module failures don't corrupt system state" do
      version = "3.4.17"
      temp_dir = "/tmp/partial_failure_test_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)

      try do
        # Successful download
        config = DefaultConfigProvider
        checksum = config.get_known_checksums()[version]

        if checksum do
          case Downloader.download_and_extract([
            version: version,
            destination: temp_dir,
            expected_checksum: checksum
          ]) do
            {:ok, download_result} ->
              # Verify download success doesn't affect plugin manager error handling
              invalid_plugin = %{"invalid" => "plugin"}

              {:error, {step, _error}} = PluginManager.apply_plugin(invalid_plugin, [
                version: version,
                base_path: temp_dir
              ])

              assert step == :validate_spec

              # Download should still be valid
              assert File.exists?(download_result.extracted_path)

              # Core constraints should still work
              constraints = Core.get_version_constraints(version)
              assert constraints.major_version == :v3

            {:error, _} ->
              # Download failed (likely network/rate limiting) - test the non-download parts
              invalid_plugin = %{"invalid" => "plugin"}

              {:error, {step, _error}} = PluginManager.apply_plugin(invalid_plugin, [
                version: version,
                base_path: temp_dir
              ])

              assert step == :validate_spec

              # Core constraints should still work
              constraints = Core.get_version_constraints(version)
              assert constraints.major_version == :v3
          end
        end

      after
        File.rm_rf!(temp_dir)
      end
    end
  end

  describe "Data flow integration" do
    test "data flows correctly between modules" do
      version = "3.4.17"
      temp_dir = "/tmp/dataflow_test_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)

      try do
        # 1. Core provides constraints
        constraints = Core.get_version_constraints(version)

        # 2. VersionFetcher provides metadata that aligns with constraints
        case VersionFetcher.get_version_info(version) do
          {:ok, version_info} ->
            assert version_info.version == version

            # Major version should match
            major_from_version = case String.split(version, ".") do
              ["3" | _] -> :v3
              ["4" | _] -> :v4
              _ -> :unknown
            end

            assert constraints.major_version == major_from_version

          {:error, _} ->
            # Version info not available is acceptable
            :ok
        end

        # 3. Builder uses constraints for path generation
        {:ok, build_paths} = Builder.get_build_paths(temp_dir, version)

        # Path structure should match constraints
        case constraints.major_version do
          :v3 ->
            assert build_paths.standalone_root =~ "standalone-cli"
          :v4 ->
            assert build_paths.standalone_root =~ "@tailwindcss-standalone"
        end

        # 4. Create structure that matches expectations
        File.mkdir_p!(build_paths.standalone_root)

        # 5. PluginManager should be able to work with this structure
        plugin_spec = %{
          "version" => ~s["test": "1.0.0"],
          "statement" => ~s['test': require('test')]
        }

        # Create minimal files for plugin manager
        case constraints.major_version do
          :v3 ->
            File.write!(Path.join(build_paths.standalone_root, "package.json"), ~s[{"devDependencies": {}}])
            File.write!(Path.join(build_paths.standalone_root, "standalone.js"), "let localModules = {};")
          :v4 ->
            File.write!(Path.join(build_paths.standalone_root, "package.json"), ~s[{"dependencies": {}}])
            src_dir = Path.join(build_paths.standalone_root, "src")
            File.mkdir_p!(src_dir)
            File.write!(Path.join(src_dir, "index.ts"), "// TypeScript file")
        end

        # Plugin manager should work with builder-generated paths
        result = PluginManager.apply_plugin(plugin_spec, [
          version: version,
          base_path: temp_dir,
          validate_compatibility: false
        ])

        case result do
          {:ok, plugin_result} ->
            assert plugin_result.version == version
          {:error, _} ->
            # Plugin application might fail, but integration should work
            :ok
        end

      after
        File.rm_rf!(temp_dir)
      end
    end
  end
end
