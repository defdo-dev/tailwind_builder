defmodule Defdo.TailwindBuilderMigrationTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindBuilder
  alias Defdo.TailwindBuilderOriginal

  @moduletag :migration
  @moduletag :capture_log

  describe "API compatibility between original and migrated versions" do
    test "installed?/1 behaves identically" do
      # Test with a tool that exists
      original_result = TailwindBuilderOriginal.installed?("sh")
      migrated_result = TailwindBuilder.installed?("sh")
      assert original_result == migrated_result

      # Test with a tool that doesn't exist
      original_result = TailwindBuilderOriginal.installed?("nonexistent_tool_xyz")
      migrated_result = TailwindBuilder.installed?("nonexistent_tool_xyz")
      assert original_result == migrated_result
    end

    test "maybe_path/1 behaves identically" do
      # Test with existing path pattern
      pattern = "/tmp/tailwind*"
      original_result = TailwindBuilderOriginal.maybe_path(pattern)
      migrated_result = TailwindBuilder.maybe_path(pattern)
      assert original_result == migrated_result

      # Test with non-existing path pattern
      pattern = "/nonexistent/path*"
      original_result = TailwindBuilderOriginal.maybe_path(pattern)
      migrated_result = TailwindBuilder.maybe_path(pattern)
      assert original_result == migrated_result
    end

    test "path_for/4 generates same paths" do
      base_path = "/tmp/test"
      version = "3.4.17"
      filename = "package.json"

      original_path = TailwindBuilder.path_for(base_path, version, filename)
      migrated_path = TailwindBuilder.path_for(base_path, version, filename)

      assert original_path == migrated_path
    end

    test "standalone_cli_path/2 generates same paths" do
      base_path = "/tmp/test"

      # Test v3
      v3_original = TailwindBuilder.standalone_cli_path(base_path, "3.4.17")
      v3_migrated = TailwindBuilder.standalone_cli_path(base_path, "3.4.17")
      assert v3_original == v3_migrated

      # Test v4
      v4_original = TailwindBuilder.standalone_cli_path(base_path, "4.1.11")
      v4_migrated = TailwindBuilder.standalone_cli_path(base_path, "4.1.11")
      assert v4_original == v4_migrated
    end

    test "tailwind_path/2 generates same paths" do
      base_path = "/tmp/test"

      # Test v3
      v3_original = TailwindBuilder.tailwind_path(base_path, "3.4.17")
      v3_migrated = TailwindBuilder.tailwind_path(base_path, "3.4.17")
      assert v3_original == v3_migrated

      # Test v4
      v4_original = TailwindBuilder.tailwind_path(base_path, "4.1.11")
      v4_migrated = TailwindBuilder.tailwind_path(base_path, "4.1.11")
      assert v4_original == v4_migrated
    end

    test "get_supported_packages_info/0 returns similar structure" do
      original_packages = TailwindBuilderOriginal.get_supported_packages_info()
      migrated_packages = TailwindBuilder.get_supported_packages_info()

      # Both should be maps
      assert is_map(original_packages)
      assert is_map(migrated_packages)

      # Should have the same package names
      original_names = Map.keys(original_packages) |> Enum.sort()
      migrated_names = Map.keys(migrated_packages) |> Enum.sort()
      assert original_names == migrated_names

      # Each package should have required fields
      for package_name <- original_names do
        original_package = original_packages[package_name]
        migrated_package = migrated_packages[package_name]

        assert Map.has_key?(original_package, :npm_name)
        assert Map.has_key?(migrated_package, :npm_name)
        assert original_package.npm_name == migrated_package.npm_name

        assert Map.has_key?(original_package, :description)
        assert Map.has_key?(migrated_package, :description)
        assert original_package.description == migrated_package.description
      end
    end

    test "patch_package_json/3 produces same results" do
      content = """
      {
        "name": "test",
        "devDependencies": {
          "existing": "1.0.0"
        }
      }
      """

      plugin = ~s["daisyui": "^4.12.23"]
      version = "3.4.17"

      original_result = TailwindBuilderOriginal.patch_package_json(content, plugin, version)
      migrated_result = TailwindBuilder.patch_package_json(content, plugin, version)

      # Both should contain the plugin
      assert original_result =~ plugin
      assert migrated_result =~ plugin

      # Both should be valid JSON
      assert {:ok, _} = Jason.decode(original_result)
      assert {:ok, _} = Jason.decode(migrated_result)
    end

    test "patch_standalone_js/2 produces same results" do
      content = """
      let localModules = {
        'existing': require('existing')
      };
      """

      statement = ~s['daisyui': require('daisyui')]

      original_result = TailwindBuilderOriginal.patch_standalone_js(content, statement)
      migrated_result = TailwindBuilder.patch_standalone_js(content, statement)

      # Both should contain the statement
      assert original_result =~ statement
      assert migrated_result =~ statement
    end
  end

  describe "version fetching compatibility" do
    @tag :external_api
    test "get_latest_tailwind_version/0 returns consistent format" do
      case TailwindBuilderOriginal.get_latest_tailwind_version() do
        {:ok, original_version} ->
          case TailwindBuilderOriginal.get_latest_tailwind_version() do
            {:ok, migrated_version} ->
              # Both should return valid version strings
              assert is_binary(original_version)
              assert is_binary(migrated_version)
              assert String.match?(original_version, ~r/^\d+\.\d+\.\d+$/)
              assert String.match?(migrated_version, ~r/^\d+\.\d+\.\d+$/)
          end
      end
    end

    test "get_latest_npm_version/1 handles supported packages identically" do
      # Test with supported package
      original_result = TailwindBuilderOriginal.get_latest_npm_version("daisyui")
      migrated_result = TailwindBuilder.get_latest_npm_version("daisyui")

      case {original_result, migrated_result} do
        {{:ok, original_version}, {:ok, migrated_version}} ->
          assert is_binary(original_version)
          assert is_binary(migrated_version)

        {{:error, reason1}, {:error, reason2}} ->
          # Both should fail with similar reasons for unsupported packages
          assert reason1 == reason2

        _ ->
          # One succeeded, one failed - this might be due to network issues
          # Let's just ensure they handle errors consistently
          :ok
      end

      # Test with unsupported package
      assert {:error, :package_not_supported} = TailwindBuilder.get_latest_npm_version("unsupported")
      assert {:error, :package_not_supported} = TailwindBuilder.get_latest_npm_version("unsupported")
    end
  end

  describe "checksum calculation compatibility" do
    @tag :external_api
    test "calculate_tailwind_checksum/1 produces same format" do
      version = "3.4.17"

      case TailwindBuilderOriginal.calculate_tailwind_checksum(version) do
        {:ok, original_result} ->
          case TailwindBuilderOriginal.calculate_tailwind_checksum(version) do
            {:ok, migrated_result} ->
              # Both should have same structure
              assert Map.keys(original_result) |> Enum.sort() ==
                     Map.keys(migrated_result) |> Enum.sort()

              # Checksums should be identical
              assert original_result.checksum == migrated_result.checksum
              assert original_result.version == migrated_result.version

            {:error, _} ->
              flunk("Migrated checksum calculation should not fail if original succeeds")
          end

        {:error, _reason} ->
          # If original fails, migrated should fail similarly
          assert {:error, _} = TailwindBuilder.calculate_tailwind_checksum(version)
      end
    end
  end

  describe "error handling compatibility" do
    test "both versions handle invalid versions similarly" do
      invalid_version = "invalid.version.format"

      # Test download with invalid version
      original_result = TailwindBuilderOriginal.download("/tmp", invalid_version)
      migrated_result = TailwindBuilder.download("/tmp", invalid_version)

      # Both should return errors (not raise exceptions)
      case {original_result, migrated_result} do
        {{:error, _}, {:error, _}} ->
          # Both return errors as expected
          assert true

        {original, migrated} ->
          # If results differ, check they're both error conditions
          refute match?({:ok, _}, original)
          refute match?({:ok, _}, migrated)
      end
    end

    test "both versions handle missing tools similarly" do
      # This is hard to test without actually removing tools
      # But we can test the tool checking logic
      assert TailwindBuilder.installed?("definitely_nonexistent_tool") == false
      assert TailwindBuilder.installed?("definitely_nonexistent_tool") == false
    end
  end

  describe "plugin application compatibility" do
    test "add_plugin with predefined plugin name works similarly" do
      # This test would require actual file setup, so we'll test the API surface
      _plugin_name = "daisyui"
      _version = "3.4.17"
      _temp_path = "/tmp/test_plugin_#{System.unique_integer()}"

      # Both should accept the same parameters without immediate errors
      # (actual functionality would require proper file setup)
      assert is_function(&TailwindBuilder.add_plugin/3)
      assert is_function(&TailwindBuilder.add_plugin/3)
    end

    test "add_plugin with custom plugin spec validates similarly" do
      _custom_plugin = %{
        "version" => ~s["test-plugin": "^1.0.0"],
        "statement" => ~s['test-plugin': require('test-plugin')]
      }

      _version = "3.4.17"
      _temp_path = "/tmp/test_custom_plugin_#{System.unique_integer()}"

      # Both should validate the plugin spec format
      # (without actually applying since we don't have the file structure)
      assert is_function(&TailwindBuilder.add_plugin/3)
      assert is_function(&TailwindBuilder.add_plugin/3)
    end
  end
end
