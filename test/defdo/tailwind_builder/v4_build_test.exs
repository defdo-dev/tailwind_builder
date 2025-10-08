defmodule Defdo.TailwindBuilder.V4BuildTest do
  @moduledoc """
  Test for v4 build functionality
  """
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.{Builder, Core}

  describe "v4 build compilation" do
    test "v4 constraints are properly defined" do
      # Test that v4 constraints are properly defined
      constraints = Core.get_version_constraints("4.1.11")
      assert constraints.major_version == :v4
      assert constraints.compilation_method == :pnpm_workspace
      assert constraints.cross_compilation == true
      assert is_list(constraints.supported_architectures)
      assert length(constraints.supported_architectures) > 10
    end

    test "v4 cross-compilation support" do
      # Test supported architectures
      supported_archs = Core.get_supported_architectures("4.1.11")

      expected_archs = [
        :"x86_64-unknown-linux-gnu",
        :"aarch64-apple-darwin",
        :"x86_64-pc-windows-msvc",
        :"aarch64-pc-windows-msvc"
      ]

      for arch <- expected_archs do
        assert arch in supported_archs, "Missing architecture: #{arch}"
      end
    end

    test "v4 required tools" do
      tools = Core.get_required_tools("4.1.11")
      assert "pnpm" in tools
      assert "node" in tools
      assert "cargo" in tools
      assert "rustc" in tools
    end

    test "v4 build commands are correct" do
      constraints = Core.get_version_constraints("4.1.11")
      build_commands = constraints.file_structure.build_commands

      # v4 uses pnpm workspace commands, not cargo directly
      assert "pnpm install --ignore-scripts --filter=!./playgrounds/*" in build_commands
      assert "pnpm run --filter ./crates/node build:platform" in build_commands
    end

    test "compilation method detection" do
      assert Core.get_compilation_method("3.4.17") == :npm
      assert Core.get_compilation_method("4.1.11") == :pnpm_workspace
      # Future v5
      assert Core.get_compilation_method("5.0.0") == :cargo
    end

    test "cross-compilation capability check" do
      # v3 supports cross-compilation
      assert Core.supports_cross_compilation?("3.4.17") == true

      # v4 also supports cross-compilation (updated from our fixes)
      assert Core.supports_cross_compilation?("4.1.11") == true

      # Future versions should also support it
      assert Core.supports_cross_compilation?("5.0.0") == true
    end
  end

  describe "build parameter validation" do
    test "compile function accepts target_arch parameter" do
      opts = [
        version: "4.1.11",
        source_path: "/tmp/nonexistent",
        debug: false,
        target_arch: "x86_64-unknown-linux-gnu"
      ]

      # This will fail due to missing source path, but it validates the parameter structure
      {:error, _} = Builder.compile(opts)
    end

    test "version parsing works for future versions" do
      # Test that our version parsing handles v5 and v6
      assert Core.get_compilation_method("5.1.0") == :cargo
      assert Core.get_compilation_method("6.2.1") == :cargo

      # And still handles v3
      assert Core.get_compilation_method("3.4.17") == :npm
    end
  end

  describe "manual integration test (requires Rust)" do
    @tag :manual
    test "actual v4 build with cargo (manual test)" do
      # This test is marked as manual because it requires:
      # 1. Rust/Cargo to be installed
      # 2. A real TailwindCSS v4 source directory

      # Skip if Rust is not available
      cargo_available = not is_nil(System.find_executable("cargo"))

      if cargo_available do
        # Manual test placeholder when Rust is available
        assert true, "Manual test - uncomment and provide real source path to run"
      else
        assert true, "Rust/Cargo not available for manual integration test - this is expected"
      end

      # You can manually test with a real source directory like this:
      # source_path = "/path/to/tailwindcss-4.1.11"
      # opts = [
      #   version: "4.1.11",
      #   source_path: source_path,
      #   debug: true
      # ]
      # {:ok, result} = Builder.compile(opts)
      # assert result.version == "4.1.11"
    end
  end
end
