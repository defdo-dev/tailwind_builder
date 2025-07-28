defmodule Defdo.TailwindBuilder.CoreFunctionsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mock
  alias Defdo.TailwindBuilder

  @moduletag :capture_log

  describe "installed?/1" do
    test "returns true when program is found" do
      with_mock System, [:passthrough], find_executable: fn "npm" -> "/usr/bin/npm" end do
        assert TailwindBuilder.installed?("npm") == true
      end
    end

    test "returns false when program is not found" do
      with_mock System, [:passthrough], find_executable: fn "nonexistent" -> nil end do
        assert TailwindBuilder.installed?("nonexistent") == false
      end
    end

    test "handles various program names" do
      with_mock System, [:passthrough],
        find_executable: fn
          "node" -> "/usr/bin/node"
          "pnpm" -> "/usr/bin/pnpm"
          "cargo" -> nil
          _ -> nil
        end do
        assert TailwindBuilder.installed?("node") == true
        assert TailwindBuilder.installed?("pnpm") == true
        assert TailwindBuilder.installed?("cargo") == false
        assert TailwindBuilder.installed?("unknown") == false
      end
    end
  end

  describe "maybe_path/1" do
    test "returns first path from wildcard matches" do
      with_mock Path, [:passthrough],
        wildcard: fn "/tmp/tailwind*" -> ["/tmp/tailwind-3.4.17", "/tmp/tailwind-4.0.0"] end do
        assert TailwindBuilder.maybe_path("/tmp/tailwind*") == "/tmp/tailwind-3.4.17"
      end
    end

    test "returns nil when no matches found" do
      with_mock Path, [:passthrough], wildcard: fn "/tmp/nonexistent*" -> [] end do
        assert TailwindBuilder.maybe_path("/tmp/nonexistent*") == nil
      end
    end

    test "returns single match" do
      with_mock Path, [:passthrough], wildcard: fn "/tmp/single*" -> ["/tmp/single-match"] end do
        assert TailwindBuilder.maybe_path("/tmp/single*") == "/tmp/single-match"
      end
    end
  end

  describe "path_for/4" do
    test "generates correct path for v3.x standalone.js" do
      path = TailwindBuilder.path_for("/tmp", "3.4.17", "standalone.js")
      expected = "/tmp/tailwindcss-3.4.17/standalone-cli/standalone.js"
      assert path == expected
    end

    test "generates correct path for v3.x package.json" do
      path = TailwindBuilder.path_for("/tmp", "3.4.17", "package.json")
      expected = "/tmp/tailwindcss-3.4.17/standalone-cli/package.json"
      assert path == expected
    end

    test "generates correct path for v4.x index.ts" do
      path = TailwindBuilder.path_for("/tmp", "4.0.9", "index.ts", "src")
      expected = "/tmp/tailwindcss-4.0.9/packages/@tailwindcss-standalone/src/index.ts"
      assert path == expected
    end

    test "generates correct path for v4.x package.json" do
      path = TailwindBuilder.path_for("/tmp", "4.0.9", "package.json")
      expected = "/tmp/tailwindcss-4.0.9/packages/@tailwindcss-standalone/package.json"
      assert path == expected
    end
  end

  describe "standalone_cli_path/2" do
    test "returns correct path for v3.x" do
      path = TailwindBuilder.standalone_cli_path("/tmp", "3.4.17")
      expected = "/tmp/tailwindcss-3.4.17/standalone-cli"
      assert path == expected
    end

    test "returns correct path for v4.x" do
      path = TailwindBuilder.standalone_cli_path("/tmp", "4.0.9")
      expected = "/tmp/tailwindcss-4.0.9/packages/@tailwindcss-standalone"
      assert path == expected
    end

    test "handles version edge cases" do
      # v4.0.0 exactly
      path = TailwindBuilder.standalone_cli_path("/tmp", "4.0.0")
      expected = "/tmp/tailwindcss-4.0.0/packages/@tailwindcss-standalone"
      assert path == expected

      # Just below v4
      path = TailwindBuilder.standalone_cli_path("/tmp", "3.9.9")
      expected = "/tmp/tailwindcss-3.9.9/standalone-cli"
      assert path == expected
    end
  end

  describe "tailwind_path/2" do
    test "returns correct base path for any version" do
      path_v3 = TailwindBuilder.tailwind_path("/tmp", "3.4.17")
      expected_v3 = "/tmp/tailwindcss-3.4.17"
      assert path_v3 == expected_v3

      path_v4 = TailwindBuilder.tailwind_path("/tmp", "4.0.9")
      expected_v4 = "/tmp/tailwindcss-4.0.9"
      assert path_v4 == expected_v4
    end
  end

  describe "patch_package_json/3" do
    test "patches package.json for v3.x with devDependencies" do
      content = """
      {
        "name": "test",
        "devDependencies": {
          "existing": "1.0.0"
        }
      }
      """

      plugin = ~s["daisyui": "^4.12.23"]
      result = TailwindBuilder.patch_package_json(content, plugin, "3.4.17")

      assert result =~ plugin
      assert result =~ "devDependencies"
    end

    test "patches package.json for v4.x with dependencies" do
      content = """
      {
        "name": "test",
        "dependencies": {
          "existing": "1.0.0"
        }
      }
      """

      plugin = ~s["daisyui": "^5.0.0"]
      result = TailwindBuilder.patch_package_json(content, plugin, "4.0.9")

      assert result =~ plugin
      assert result =~ "dependencies"
    end

    test "skips patching if already present" do
      plugin = ~s["daisyui": "^4.12.23"]

      content = """
      {
        "name": "test",
        "devDependencies": {
          #{plugin}
        }
      }
      """

      log =
        capture_log(fn ->
          result = TailwindBuilder.patch_package_json(content, plugin, "3.4.17")
          assert result == content
        end)

      assert log =~ "It's previously patched"
    end

    test "handles patch errors gracefully" do
      # Test with malformed JSON that can't be parsed
      content = """
      {
        "name": "test"
        "devDependencies" {
          // invalid syntax
        }
      """

      plugin = ~s["daisyui": "^4.12.23"]
      result = TailwindBuilder.patch_package_json(content, plugin, "3.4.17")

      # With the new JSON implementation, this should fallback to string patching
      # and fail because the content doesn't have the expected structure
      assert result == {:error, :unable_to_patch}
    end
  end

  describe "patch_standalone_js/2" do
    test "patches standalone.js with plugin statement" do
      content = """
      let localModules = {
        'existing': require('existing')
      };
      """

      statement = ~s['daisyui': require('daisyui')]
      result = TailwindBuilder.patch_standalone_js(content, statement)

      assert result =~ statement
      assert result =~ "localModules"
    end

    test "skips patching if already present" do
      statement = ~s['daisyui': require('daisyui')]

      content = """
      let localModules = {
        #{statement}
      };
      """

      log =
        capture_log(fn ->
          result = TailwindBuilder.patch_standalone_js(content, statement)
          assert result == content
        end)

      assert log =~ "It's previously patched"
    end

    test "handles patch errors gracefully" do
      # Content without target pattern
      content = "invalid javascript content"
      statement = ~s['daisyui': require('daisyui')]

      result = TailwindBuilder.patch_standalone_js(content, statement)
      assert result == {:error, :unable_to_patch}
    end
  end

  describe "patch_index_ts/2" do
    test "patches index.ts with available modifications for new plugin" do
      content = """
      // Some TypeScript content
      id.startsWith('@tailwindcss/') ||
      """

      result = TailwindBuilder.patch_index_ts(content, "daisyui")

      # Verify at least the basic patch is applied
      assert result =~ "id.startsWith('daisyui') ||"

      # The result should be different from input (some patch was applied)
      assert result != content
    end

    test "skips patching if plugin already exists" do
      content = """
      id.startsWith('daisyui') ||
      'daisyui': await import('daisyui')
      """

      log =
        capture_log(fn ->
          result = TailwindBuilder.patch_index_ts(content, "daisyui")
          assert result == content
        end)

      assert log =~ "already patched"
    end

    test "handles multiple plugin patches" do
      content = """
      id.startsWith('@tailwindcss/') ||
      'tailwindcss/defaultTheme.js': await import('tailwindcss/defaultTheme'),
      """

      # First plugin
      result1 = TailwindBuilder.patch_index_ts(content, "daisyui")
      assert result1 =~ "daisyui"

      # Second plugin on top of first
      result2 = TailwindBuilder.patch_index_ts(result1, "autoprefixer")
      assert result2 =~ "daisyui"
      assert result2 =~ "autoprefixer"
    end
  end

  describe "available plugins" do
    test "has predefined daisyui plugin configuration" do
      # Test plugin configuration without file operations
      with_mock File, [:passthrough],
        exists?: fn _ -> true end,
        read!: fn
          path ->
            cond do
              String.contains?(path, "package.json") ->
                """
                {
                  "devDependencies": {
                    "existing": "1.0.0"
                  }
                }
                """

              String.contains?(path, "standalone.js") ->
                """
                let localModules = {
                  'existing': require('existing')
                };
                """

              true ->
                "mock content"
            end
        end,
        write!: fn _, _ -> :ok end do
        result = TailwindBuilder.add_plugin("daisyui", "3.4.17", "/tmp/test")
        assert is_list(result)
        # package.json and standalone.js patches
        assert length(result) == 2
      end
    end

    test "handles custom plugin with version and statement" do
      custom_plugin = %{
        "version" => ~s["custom-plugin": "^1.0.0"],
        "statement" => ~s['custom-plugin': require('custom-plugin')]
      }

      with_mock File, [:passthrough],
        exists?: fn _ -> true end,
        read!: fn
          path ->
            cond do
              String.contains?(path, "package.json") ->
                """
                {
                  "devDependencies": {
                    "existing": "1.0.0"
                  }
                }
                """

              String.contains?(path, "standalone.js") ->
                """
                let localModules = {
                  'existing': require('existing')
                };
                """

              true ->
                "mock content"
            end
        end,
        write!: fn _, _ -> :ok end do
        result = TailwindBuilder.add_plugin(custom_plugin, "3.4.17", "/tmp/test")
        assert is_list(result)
      end
    end

    test "validates custom plugin format" do
      invalid_plugin = %{
        "version" => "invalid-format-without-colon"
      }

      assert_raise RuntimeError, ~r/Be sure that you have a valid values/, fn ->
        TailwindBuilder.add_plugin(invalid_plugin, "3.4.17", "/tmp/test")
      end
    end
  end

  describe "version comparison and branching" do
    test "correctly identifies v3.x vs v4.x behavior" do
      # Test that different versions use different file structures

      # v3.x should use standalone-cli structure
      v3_path = TailwindBuilder.standalone_cli_path("/tmp", "3.4.17")
      assert v3_path =~ "standalone-cli"

      # v4.x should use packages/@tailwindcss-standalone structure
      v4_path = TailwindBuilder.standalone_cli_path("/tmp", "4.0.9")
      assert v4_path =~ "packages/@tailwindcss-standalone"
    end

    test "handles edge case versions correctly" do
      # Version exactly at boundary
      v4_exact = TailwindBuilder.standalone_cli_path("/tmp", "4.0.0")
      assert v4_exact =~ "packages/@tailwindcss-standalone"

      # Version just below boundary
      v3_high = TailwindBuilder.standalone_cli_path("/tmp", "3.99.99")
      assert v3_high =~ "standalone-cli"
    end
  end
end
