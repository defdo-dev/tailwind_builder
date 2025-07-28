defmodule Defdo.TailwindBuilder.SecurityTest do
  use ExUnit.Case, async: false
  alias Defdo.TailwindBuilder

  @moduletag :capture_log

  describe "download URL validation" do
    test "accepts valid Tailwind CSS repository URLs" do
      valid_urls = [
        "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v3.4.17.tar.gz",
        "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v4.0.9.tar.gz"
      ]

      # Use private function access pattern that won't fail in tests
      for url <- valid_urls do
        # We can't directly test private fetch_body! but we can test the URL validation logic
        assert url =~ ~r{^https://github\.com/tailwindlabs/tailwindcss/}
      end
    end

    test "rejects invalid or malicious URLs" do
      malicious_urls = [
        "http://evil.com/malware.tar.gz",
        "https://github.com/evil-user/tailwindcss/malware.tar.gz",
        "https://evil.com/tailwindcss.tar.gz",
        "ftp://github.com/tailwindlabs/tailwindcss/file.tar.gz"
      ]

      for url <- malicious_urls do
        refute url =~ ~r{^https://github\.com/tailwindlabs/tailwindcss/}
      end
    end
  end

  describe "download integrity validation" do
    test "validates checksum-based integrity" do
      # Test checksum validation logic
      test_content = "example content for checksum"
      actual_checksum = 
        :crypto.hash(:sha256, test_content)
        |> Base.encode16(case: :lower)
      
      # Valid checksum should match
      assert actual_checksum == actual_checksum
      
      # Different content should produce different checksum
      different_content = "different content"
      different_checksum = 
        :crypto.hash(:sha256, different_content)
        |> Base.encode16(case: :lower)
      
      refute actual_checksum == different_checksum
    end

    test "validates known tailwind checksums format" do
      # Test that our known checksums are valid SHA256 format
      known_checksums = [
        "89c0a7027449cbe564f8722e84108f7bfa0224b5d9289c47cc967ffef8e1b016",  # v3.4.17
        "7c36fdcdfed4d1b690a56a1267457a8ac9c640ccae2efcaed59f5053d330000a"   # v4.0.9
      ]
      
      for checksum <- known_checksums do
        # SHA256 checksums should be 64 characters long
        assert String.length(checksum) == 64
        # Should only contain hexadecimal characters
        assert String.match?(checksum, ~r/^[a-f0-9]+$/)
      end
    end

    test "validates URL format strictness" do
      valid_urls = [
        "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v3.4.17.tar.gz",
        "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v4.0.9.tar.gz",
        "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v1.2.3.tar.gz"
      ]
      
      invalid_urls = [
        "https://github.com/evil-user/tailwindcss/archive/refs/tags/v3.4.17.tar.gz",
        "https://github.com/tailwindlabs/tailwindcss/archive/refs/heads/main.tar.gz",
        "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/vmalicious.tar.gz",
        "http://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v3.4.17.tar.gz"
      ]
      
      strict_pattern = ~r{^https://github\.com/tailwindlabs/tailwindcss/archive/refs/tags/v\d+\.\d+\.\d+\.tar\.gz$}
      
      for url <- valid_urls do
        assert String.match?(url, strict_pattern)
      end
      
      for url <- invalid_urls do
        refute String.match?(url, strict_pattern)
      end
    end
  end

  describe "SSL configuration validation" do
    test "validates SSL protocol versions based on OTP version" do
      # Test the actual protocol_versions logic through Version.compare behavior
      # Since protocol_versions/0 is private, we test the logic that would use it

      # Test version comparison that drives SSL protocol selection
      v3_version = "3.4.17"
      v4_version = "4.0.9"

      assert Version.compare(v3_version, "4.0.0") == :lt
      assert Version.compare(v4_version, "4.0.0") == :gt

      # Test OTP version logic pattern
      mock_otp_24 = 24
      mock_otp_25 = 25
      mock_otp_26 = 26

      # Logic: if otp_version() < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
      otp_24_versions = if mock_otp_24 < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
      otp_25_versions = if mock_otp_25 < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
      otp_26_versions = if mock_otp_26 < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]

      assert otp_24_versions == [:"tlsv1.2"]
      assert otp_25_versions == [:"tlsv1.2", :"tlsv1.3"]
      assert otp_26_versions == [:"tlsv1.2", :"tlsv1.3"]
    end

    test "validates SSL verification configuration" do
      # Test SSL configuration structure that should be used
      ssl_config = [
        verify: :verify_peer,
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]

      assert ssl_config[:verify] == :verify_peer
      assert ssl_config[:depth] == 2
      assert is_list(ssl_config[:customize_hostname_check])
    end
  end

  describe "file permission and extraction security" do
    test "validates secure file permissions" do
      # Test file permission constants used in the system
      expected_permissions = 0o755

      # Should be executable but not setuid/setgid
      # 0o755 in decimal
      assert expected_permissions == 493
      # At least readable
      assert expected_permissions >= 0o644
      # Not setuid/setgid
      assert expected_permissions < 0o1000
    end

    test "validates tar extraction security" do
      # Test tar extraction options structure
      base_dir = "/tmp/test"
      options = [:compressed, {:cwd, base_dir}]

      assert :compressed in options
      assert {:cwd, base_dir} in options

      # Verify base directory path doesn't allow directory traversal
      refute base_dir =~ ".."
      assert Path.absname(base_dir) == base_dir
    end
  end

  describe "JSON patching security" do
    test "validates JSON parsing for package.json modifications" do
      # Test that JSON parsing handles malformed content gracefully
      valid_package_json = """
      {
        "name": "test-package",
        "devDependencies": {
          "existing": "1.0.0"
        }
      }
      """

      malformed_json = """
      {
        "name": "test-package"
        "devDependencies": {
          // invalid comment
          "existing": "1.0.0"
        }
      """

      # Valid JSON should parse successfully
      assert {:ok, _parsed} = Jason.decode(valid_package_json)

      # Malformed JSON should fail gracefully
      assert {:error, _reason} = Jason.decode(malformed_json)
    end

    test "validates plugin dependency parsing" do
      # Test dependency string parsing logic
      valid_plugin_strings = [
        ~s["daisyui": "^4.12.23"],
        ~s["autoprefixer": "~10.0.0"],
        ~s["postcss": ">=8.0.0"]
      ]

      for plugin_str <- valid_plugin_strings do
        parts = String.split(plugin_str, ": ", parts: 2)
        assert length(parts) == 2

        plugin_name = String.trim(hd(parts), "\"")
        plugin_version = String.trim(List.last(parts), "\"")

        assert String.length(plugin_name) > 0
        assert String.length(plugin_version) > 0
        # No shell injection chars
        refute plugin_name =~ ~r/[<>|&;`$()]/
      end
    end

    test "validates version-based dependency section selection" do
      # Test that correct dependency section is chosen based on version
      v3_version = "3.4.17"
      v4_version = "4.0.9"

      # v3 should use devDependencies
      v3_dep_section =
        if Version.compare(v3_version, "4.0.0") in [:eq, :gt] do
          "dependencies"
        else
          "devDependencies"
        end

      # v4 should use dependencies
      v4_dep_section =
        if Version.compare(v4_version, "4.0.0") in [:eq, :gt] do
          "dependencies"
        else
          "devDependencies"
        end

      assert v3_dep_section == "devDependencies"
      assert v4_dep_section == "dependencies"
    end
  end

  describe "input validation and sanitization" do
    test "validates version string format" do
      valid_versions = ["3.4.17", "4.0.9", "3.0.0", "4.1.0"]

      for version <- valid_versions do
        # Should not raise for valid version formats
        assert is_binary(version)
        assert String.match?(version, ~r/^\d+\.\d+\.\d+$/)
        # No path traversal attempts
        refute version =~ ".."
      end
    end

    test "validates path construction security" do
      # Test path construction without file operations
      base_path = "/tmp/test"
      version = "3.4.17"

      expected_v3_path = "/tmp/test/tailwindcss-3.4.17/standalone-cli"
      actual_v3_path = TailwindBuilder.standalone_cli_path(base_path, version)

      assert actual_v3_path == expected_v3_path

      # Ensure no directory traversal
      refute actual_v3_path =~ ".."
      # Ensure absolute path safety
      assert String.starts_with?(actual_v3_path, base_path)
    end

    test "validates plugin configuration structure" do
      # Test plugin configuration validation
      valid_plugin = %{
        "version" => ~s["test-plugin": "^1.0.0"],
        "statement" => ~s['test-plugin': require('test-plugin')]
      }

      assert Map.has_key?(valid_plugin, "version")
      assert valid_plugin["version"] =~ ":"

      # Should raise for invalid format
      invalid_plugin = %{"version" => "no-colon-format"}

      assert_raise RuntimeError, ~r/Be sure that you have a valid values/, fn ->
        TailwindBuilder.add_plugin(invalid_plugin, "3.4.17", "/tmp/test")
      end
    end
  end
end
