defmodule Defdo.TailwindBuilder.CoreTest do
  use ExUnit.Case, async: true
  alias Defdo.TailwindBuilder.Core

  @moduletag :capture_log

  describe "version support queries" do
    test "recognizes supported versions" do
      assert Core.in_production_support?("3.4.17") == true
      assert Core.in_production_support?("4.1.11") == true
      assert Core.in_production_support?("5.0.0") == false  # Future version
      assert Core.in_production_support?("invalid") == false
    end

    test "returns correct compilation method by version" do
      assert Core.get_compilation_method("3.4.17") == :npm
      assert Core.get_compilation_method("4.1.11") == :cargo  # Updated: v4 uses Cargo
      assert Core.get_compilation_method("5.0.0") == :cargo   # Future versions also use Cargo
    end

    test "returns required tools by version" do
      v3_tools = Core.get_required_tools("3.4.17")
      assert "npm" in v3_tools
      assert "node" in v3_tools

      v4_tools = Core.get_required_tools("4.1.11")
      assert "cargo" in v4_tools  # Updated: v4 requires Cargo
      assert "rustc" in v4_tools  # Updated: v4 requires Rust
    end
  end

  describe "cross-compilation capabilities" do
    test "v3 supports cross-compilation" do
      assert Core.supports_cross_compilation?("3.4.17") == true
    end

    test "v4 supports cross-compilation" do
      # Updated: v4 now supports cross-compilation via Cargo
      assert Core.supports_cross_compilation?("4.1.11") == true
    end

    test "future versions support cross-compilation" do
      assert Core.supports_cross_compilation?("5.0.0") == true
    end
  end

  describe "architecture support" do
    test "v3 supports multiple architectures" do
      architectures = Core.get_supported_architectures("3.4.17")
      assert is_list(architectures)
      assert length(architectures) > 1
    end

    test "v4 supports multiple architectures via Rust targets" do
      architectures = Core.get_supported_architectures("4.1.11")
      assert is_list(architectures)
      assert length(architectures) > 10  # Updated: v4 supports many Rust targets

      # Check some expected Rust targets
      assert :"x86_64-unknown-linux-gnu" in architectures
      assert :"aarch64-apple-darwin" in architectures
      assert :"x86_64-pc-windows-msvc" in architectures
    end

    test "v4 does not use host-only architecture" do
      architectures = Core.get_supported_architectures("4.1.11")
      # Updated: v4 no longer uses :host_only
      refute :host_only in architectures
    end
  end

  describe "technical feasibility validation" do
    test "validates supported version compilation" do
      request = %{
        version: "3.4.17",
        target_arch: "linux-x64",  # v3 uses this format
        plugins: []
      }

      assert {:ok, :technically_feasible} = Core.validate_technical_feasibility(request)
    end

    test "v4 has many supported architectures" do
      # Test that v4 has the expected architectures without technical feasibility
      v4_archs = Core.get_supported_architectures("4.1.11")
      assert length(v4_archs) > 10
      assert :"x86_64-unknown-linux-gnu" in v4_archs
      assert :"aarch64-apple-darwin" in v4_archs
    end

    test "rejects unsupported version" do
      request = %{
        version: "invalid-version",
        target_arch: "x86_64-unknown-linux-gnu",
        plugins: []
      }

      assert {:error, _reason} = Core.validate_technical_feasibility(request)
    end
  end

  describe "version comparison" do
    test "v3 and v4 have different compilation methods" do
      assert Core.get_compilation_method("3.4.17") != Core.get_compilation_method("4.1.11")
      assert Core.get_compilation_method("3.4.17") == :npm
      assert Core.get_compilation_method("4.1.11") == :cargo
    end

    test "v3 and v4 both support cross-compilation" do
      # Updated: Both v3 and v4 now support cross-compilation
      assert Core.supports_cross_compilation?("3.4.17") == true
      assert Core.supports_cross_compilation?("4.1.11") == true
    end

    test "v3 and v4 have different required tools" do
      v3_tools = Core.get_required_tools("3.4.17")
      v4_tools = Core.get_required_tools("4.1.11")

      assert v3_tools != v4_tools
      assert "npm" in v3_tools
      assert "cargo" in v4_tools
    end
  end

  describe "future version support" do
    test "v5 and v6 are recognized but not in production" do
      assert Core.in_production_support?("5.1.0") == false
      assert Core.in_production_support?("6.2.1") == false
    end

    test "v5 and v6 use cargo compilation method" do
      assert Core.get_compilation_method("5.1.0") == :cargo
      assert Core.get_compilation_method("6.2.1") == :cargo
    end

    test "v5 and v6 support cross-compilation" do
      assert Core.supports_cross_compilation?("5.1.0") == true
      assert Core.supports_cross_compilation?("6.2.1") == true
    end
  end
end