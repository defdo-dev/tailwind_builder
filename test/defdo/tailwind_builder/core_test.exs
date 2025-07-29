defmodule Defdo.TailwindBuilder.CoreTest do
  use ExUnit.Case, async: true
  alias Defdo.TailwindBuilder.Core

  @moduletag :capture_log

  describe "version support queries" do
    test "recognizes supported versions" do
      assert Core.in_production_support?("3.4.17") == true
      assert Core.in_production_support?("4.1.11") == true
      assert Core.in_production_support?("invalid") == false
    end

    test "returns correct compilation method by version" do
      assert Core.get_compilation_method("3.4.17") == :npm
      assert Core.get_compilation_method("4.1.11") == :rust
    end

    test "returns required tools by version" do
      v3_tools = Core.get_required_tools("3.4.17")
      assert "npm" in v3_tools
      assert "node" in v3_tools

      v4_tools = Core.get_required_tools("4.1.11")
      assert "pnpm" in v4_tools
      assert "node" in v4_tools
    end
  end

  describe "cross-compilation capabilities" do
    test "v3 supports cross-compilation" do
      assert Core.supports_cross_compilation?("3.4.17") == true
    end

    test "v4 does not support cross-compilation" do
      assert Core.supports_cross_compilation?("4.1.11") == false
    end

    test "cross-compilation check combines version and target support" do
      # v3 can cross-compile to any supported architecture
      assert Core.can_cross_compile?("3.4.17", "linux-x64") == true
      assert Core.can_cross_compile?("3.4.17", "darwin-arm64") == true
      
      # v4 cannot cross-compile to any architecture
      assert Core.can_cross_compile?("4.1.11", "linux-x64") == false
      assert Core.can_cross_compile?("4.1.11", "darwin-arm64") == false
    end
  end

  describe "architecture support" do
    test "v3 supports multiple architectures" do
      architectures = Core.get_supported_architectures("3.4.17")
      assert is_list(architectures)
      assert length(architectures) > 1
      assert "linux-x64" in architectures
      assert "darwin-x64" in architectures
    end

    test "v4 is host-only" do
      architectures = Core.get_supported_architectures("4.1.11")
      assert architectures == [:host_only]
    end

    test "host architecture detection works" do
      host_arch = Core.get_host_architecture()
      assert is_binary(host_arch)
      assert host_arch =~ ~r/^(linux|darwin|win32|freebsd)-(x64|arm64|arm)$/
    end
  end

  describe "technical feasibility validation" do
    test "validates supported version compilation" do
      request = %{
        version: "3.4.17",
        target_arch: "linux-x64",
        plugins: []
      }
      
      assert {:ok, :technically_feasible} = Core.validate_technical_feasibility(request)
    end

    test "rejects unsupported version" do
      request = %{
        version: "invalid-version",
        target_arch: "linux-x64",
        plugins: []
      }
      
      assert {:error, {:not_technically_feasible, :version_not_supported}} = 
        Core.validate_technical_feasibility(request)
    end

    test "validates architecture constraints for v4" do
      request = %{
        version: "4.1.11",
        target_arch: "different-from-host",  # This should fail since v4 can't cross-compile
        plugins: []
      }
      
      # This will fail unless target_arch happens to match host
      case Core.validate_technical_feasibility(request) do
        {:ok, :technically_feasible} -> 
          # target_arch must have matched host architecture
          assert request.target_arch == Core.get_host_architecture()
        {:error, {:not_technically_feasible, :architecture_not_supported}} ->
          # Expected for cross-compilation attempt on v4
          assert true
      end
    end
  end

  describe "convenience functions" do
    test "get_preferred_package_manager returns correct manager" do
      assert Core.get_preferred_package_manager("3.4.17") == "npm"
      assert Core.get_preferred_package_manager("4.1.11") == "pnpm"
    end

    test "can_compile_on_current_system works for supported versions" do
      # Should work for supported versions targeting host architecture
      assert Core.can_compile_on_current_system?("3.4.17") == true
      assert Core.can_compile_on_current_system?("4.1.11") == true
      
      # Should fail for unsupported version
      assert Core.can_compile_on_current_system?("invalid") == false
    end

    test "get_version_summary provides comprehensive overview" do
      summary = Core.get_version_summary("3.4.17")
      
      assert summary.version == "3.4.17"
      assert summary.compilation_method == :npm
      assert summary.cross_compilation == true
      assert is_integer(summary.supported_architectures)
      assert summary.supported_architectures > 1
      assert is_boolean(summary.can_compile_from_current_host)
      assert is_list(summary.required_tools)
      assert is_list(summary.limitations)
    end
  end

  describe "version comparison" do
    test "compare_versions shows differences between v3 and v4" do
      comparison = Core.compare_versions("3.4.17", "4.1.11")
      
      assert comparison.version1.version == "3.4.17"
      assert comparison.version2.version == "4.1.11"
      
      # These should be different between v3 and v4
      assert comparison.differences.compilation_method == true
      assert comparison.differences.cross_compilation == true
      assert comparison.differences.tool_requirements == true
    end

    test "compare_versions shows no differences for same major version" do
      comparison = Core.compare_versions("4.0.9", "4.1.11")
      
      # These should be the same for both v4 versions
      assert comparison.differences.compilation_method == false
      assert comparison.differences.cross_compilation == false
      # Tools might be the same
    end
  end

  describe "technical requirements" do
    test "get_technical_requirements for compilation operation" do
      requirements = Core.get_technical_requirements(:compile_version, %{version: "3.4.17"})
      
      assert Map.has_key?(requirements, :required_tools)
      assert Map.has_key?(requirements, :runtime_constraints)
      assert Map.has_key?(requirements, :build_commands)
      assert is_list(requirements.required_tools)
      assert is_list(requirements.build_commands)
    end

    test "get_technical_requirements for cross-compilation" do
      requirements = Core.get_technical_requirements(:cross_compile, %{
        version: "3.4.17", 
        target_arch: "linux-x64"
      })
      
      assert Map.has_key?(requirements, :cross_compilation)
      cross_comp = requirements.cross_compilation
      assert cross_comp.supported == true
      assert cross_comp.target_architecture == "linux-x64"
    end

    test "cross-compilation requirements show limitations for v4" do
      requirements = Core.get_technical_requirements(:cross_compile, %{
        version: "4.1.11", 
        target_arch: "linux-x64"
      })
      
      cross_comp = requirements.cross_compilation
      assert cross_comp.supported == false
      assert Map.has_key?(cross_comp, :reason)
      assert Map.has_key?(cross_comp, :alternative)
    end
  end

  describe "technical limitations" do
    test "get_technical_limitations provides comprehensive constraints" do
      limitations = Core.get_technical_limitations("4.1.11")
      
      assert limitations.version == "4.1.11"
      assert Map.has_key?(limitations, :compilation_limitations)
      assert Map.has_key?(limitations, :architecture_constraints)
      assert Map.has_key?(limitations, :toolchain_constraints)
      assert Map.has_key?(limitations, :file_system_constraints)
      
      # v4 specific constraints
      assert limitations.architecture_constraints.host_only == true
      assert limitations.architecture_constraints.cross_compilation == false
    end

    test "v3 and v4 have different limitations" do
      v3_limitations = Core.get_technical_limitations("3.4.17")
      v4_limitations = Core.get_technical_limitations("4.1.11")
      
      # Cross-compilation support differs
      assert v3_limitations.architecture_constraints.cross_compilation == true
      assert v4_limitations.architecture_constraints.cross_compilation == false
      
      # Required tools differ
      refute v3_limitations.toolchain_constraints.required_tools == 
             v4_limitations.toolchain_constraints.required_tools
    end
  end

  describe "operation possibility checks" do
    test "is_technically_possible for various operations" do
      # Cross-compilation possible for v3
      assert Core.is_technically_possible?(:cross_compile, %{
        version: "3.4.17", 
        target_arch: "linux-x64"
      }) == true
      
      # Cross-compilation not possible for v4
      assert Core.is_technically_possible?(:cross_compile, %{
        version: "4.1.11", 
        target_arch: "linux-x64"
      }) == false
      
      # Version compilation
      assert Core.is_technically_possible?(:compile_version, %{version: "3.4.17"}) == true
      assert Core.is_technically_possible?(:compile_version, %{version: "invalid"}) == false
      
      # Package manager usage
      assert Core.is_technically_possible?(:use_package_manager, %{
        version: "3.4.17", 
        manager: "npm"
      }) == true
      
      assert Core.is_technically_possible?(:use_package_manager, %{
        version: "4.1.11", 
        manager: "pnpm"
      }) == true
    end
  end
end