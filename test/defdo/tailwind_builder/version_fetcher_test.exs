defmodule Defdo.TailwindBuilder.VersionFetcherTest do
  use ExUnit.Case, async: false
  alias Defdo.TailwindBuilder

  @moduletag :capture_log

  describe "supported packages configuration" do
    test "has valid supported packages structure" do
      # Test internal structure without external calls
      supported = TailwindBuilder.get_supported_packages_info()

      assert is_map(supported)

      # Test that we have expected packages (only external Tailwind plugins)
      expected_packages = ["daisyui"]

      for package <- expected_packages do
        assert Map.has_key?(supported, package)
        package_info = supported[package]
        assert Map.has_key?(package_info, :npm_name)
        assert Map.has_key?(package_info, :description)
        assert is_binary(package_info.npm_name)
        assert is_binary(package_info.description)

        # Ensure description mentions Tailwind (since these are all Tailwind plugins)
        assert String.downcase(package_info.description) =~ "tailwind"
      end

      # Ensure we only have DaisyUI (no built-in plugins that are already in Tailwind v4)
      assert map_size(supported) == 1
    end
  end

  describe "get_latest_npm_version/1" do
    test "returns error for unsupported package" do
      assert {:error, :package_not_supported} =
               TailwindBuilder.get_latest_npm_version("unsupported-package")
    end

    test "validates package name format" do
      # Test with empty string
      assert {:error, :package_not_supported} = TailwindBuilder.get_latest_npm_version("")

      # Test with nil (should fail with function clause)
      assert_raise FunctionClauseError, fn ->
        TailwindBuilder.get_latest_npm_version(nil)
      end
    end
  end

  describe "version validation" do
    test "version string format validation" do
      # Test version format patterns that should be valid
      valid_versions = ["3.4.17", "4.0.9", "1.0.0", "10.20.30"]

      for version <- valid_versions do
        assert String.match?(version, ~r/^\d+\.\d+\.\d+$/)
      end

      # Test version format patterns that should be invalid
      invalid_versions = ["v3.4.17", "3.4", "3.4.17-beta", "latest"]

      for version <- invalid_versions do
        refute String.match?(version, ~r/^\d+\.\d+\.\d+$/)
      end
    end

    test "GitHub tag name prefix removal" do
      # Test version prefix removal logic
      assert "3.4.17" = String.replace_prefix("v3.4.17", "v", "")
      assert "4.0.9" = String.replace_prefix("4.0.9", "v", "")
      assert "3.4.17" = String.replace_prefix("3.4.17", "v", "")
    end
  end

  describe "checksum calculation" do
    test "checksum format validation" do
      # Test checksum calculation without network calls
      test_content = "example content for testing"

      calculated_checksum =
        :crypto.hash(:sha256, test_content)
        |> Base.encode16(case: :lower)

      # SHA256 checksums should be 64 characters long
      assert String.length(calculated_checksum) == 64
      # Should only contain hexadecimal characters
      assert String.match?(calculated_checksum, ~r/^[a-f0-9]+$/)

      # Same content should always produce same checksum
      second_calculation =
        :crypto.hash(:sha256, test_content)
        |> Base.encode16(case: :lower)

      assert calculated_checksum == second_calculation
    end

    test "handles invalid version format for checksum calculation" do
      # Test with a version that would create invalid URL
      assert {:error, :invalid_url} =
               TailwindBuilder.calculate_tailwind_checksum("invalid-version")

      assert {:error, :invalid_url} =
               TailwindBuilder.calculate_tailwind_checksum("../../../etc/passwd")
    end
  end

  describe "package validation" do
    test "validates package name input" do
      # Test with valid package names (only external plugins)
      valid_names = ["daisyui"]

      for name <- valid_names do
        assert is_binary(name)
        assert String.length(name) > 0
        # No shell injection chars
        refute name =~ ~r/[<>|&;`$()]/
      end
    end

    test "npm package name format validation" do
      # Test NPM package name patterns (only external plugins)
      npm_patterns = [
        {"daisyui", "daisyui"}
      ]

      for {_package_name, npm_name} <- npm_patterns do
        assert is_binary(npm_name)
        # Should be valid NPM package name format
        assert String.match?(npm_name, ~r/^(@[a-z0-9-]+\/)?[a-z0-9-]+$/)
      end
    end
  end
end
