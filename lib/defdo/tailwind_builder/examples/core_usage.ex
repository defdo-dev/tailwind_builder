defmodule Defdo.TailwindBuilder.Examples.CoreUsage do
  @moduledoc """
  Example usage of the Core module demonstrating separation of concerns.

  This shows how the Core only exposes technical facts, while upper layers
  can implement business logic and policies on top of these constraints.
  """

  alias Defdo.TailwindBuilder.Core

  @doc """
  Example: Technical constraint checking without business logic
  """
  def demonstrate_technical_constraints do
    IO.puts("=== Technical Constraints Demo ===")

    # Technical fact: What can v3 do?
    v3_summary = Core.get_version_summary("3.4.17")
    IO.puts("Tailwind v3.4.17:")
    IO.puts("  - Compilation method: #{v3_summary.compilation_method}")
    IO.puts("  - Cross-compilation: #{v3_summary.cross_compilation}")
    IO.puts("  - Supported architectures: #{v3_summary.supported_architectures}")
    IO.puts("  - Required tools: #{inspect(v3_summary.required_tools)}")
    IO.puts("")

    # Technical fact: What can v4 do?
    v4_summary = Core.get_version_summary("4.1.11")
    IO.puts("Tailwind v4.1.11:")
    IO.puts("  - Compilation method: #{v4_summary.compilation_method}")
    IO.puts("  - Cross-compilation: #{v4_summary.cross_compilation}")
    IO.puts("  - Available targets from host: #{v4_summary.available_targets_from_host}")
    IO.puts("  - Required tools: #{inspect(v4_summary.required_tools)}")
    IO.puts("  - Limitations: #{inspect(v4_summary.limitations)}")
    IO.puts("")

    # Technical comparison
    comparison = Core.compare_versions("3.4.17", "4.1.11")
    IO.puts("Key technical differences:")
    for {aspect, different?} <- comparison.differences do
      if different?, do: IO.puts("  - #{aspect}: DIFFERENT")
    end
  end

  @doc """
  Example: Cross-compilation feasibility checking
  """
  def demonstrate_cross_compilation_analysis do
    IO.puts("=== Cross-Compilation Analysis ===")

    target_architectures = ["linux-x64", "darwin-arm64", "win32-x64"]
    versions = ["3.4.17", "4.1.11"]

    for version <- versions do
      IO.puts("#{version}:")
      for arch <- target_architectures do
        can_compile = Core.can_cross_compile?(version, arch)
        status = if can_compile, do: "✓ POSSIBLE", else: "✗ NOT POSSIBLE"
        IO.puts("  #{arch}: #{status}")
      end
      IO.puts("")
    end

    # Show current host capabilities
    host_arch = Core.get_host_architecture()
    IO.puts("Current host architecture: #{host_arch}")

    for version <- versions do
      available_targets = Core.get_available_targets(version)
      IO.puts("#{version} can compile for: #{inspect(available_targets)}")
    end
  end

  @doc """
  Example: Technical requirements for operations
  """
  def demonstrate_technical_requirements do
    IO.puts("=== Technical Requirements Analysis ===")

    # What do we need to compile v3?
    v3_reqs = Core.get_technical_requirements(:compile_version, %{version: "3.4.17"})
    IO.puts("To compile Tailwind v3.4.17:")
    IO.puts("  - Required tools: #{inspect(v3_reqs.required_tools)}")
    IO.puts("  - Build commands: #{inspect(v3_reqs.build_commands)}")
    IO.puts("  - Working directory: #{v3_reqs.working_directory}")
    IO.puts("")

    # What do we need to compile v4?
    v4_reqs = Core.get_technical_requirements(:compile_version, %{version: "4.1.11"})
    IO.puts("To compile Tailwind v4.1.11:")
    IO.puts("  - Required tools: #{inspect(v4_reqs.required_tools)}")
    IO.puts("  - Build commands: #{inspect(v4_reqs.build_commands)}")
    IO.puts("  - Working directory: #{v4_reqs.working_directory}")
    IO.puts("")

    # Cross-compilation requirements
    cross_reqs = Core.get_technical_requirements(:cross_compile, %{
      version: "4.1.11",
      target_arch: "linux-x64"
    })
    IO.puts("Cross-compiling v4.1.11 to linux-x64:")
    IO.puts("  - Supported: #{cross_reqs.cross_compilation.supported}")
    IO.puts("  - Reason: #{cross_reqs.cross_compilation[:reason]}")
    IO.puts("  - Alternative: #{cross_reqs.cross_compilation[:alternative]}")
  end

  @doc """
  Example: This is where business logic would go (NOT in Core)

  The Core only tells us what's technically possible.
  Business logic decides what we SHOULD do based on policies.
  """
  def demonstrate_business_logic_separation do
    IO.puts("=== Business Logic Layer (NOT in Core) ===")

    # Business decision: Should we recommend v3 or v4?
    # This involves policies, not just technical constraints

    user_needs_cross_compilation = true

    recommendation = if user_needs_cross_compilation do
      # Business policy: If user needs cross-compilation, recommend v3
      # Even though v4 has newer features
      %{
        recommended_version: "3.4.17",
        reason: "Cross-compilation requirement",
        technical_basis: Core.supports_cross_compilation?("3.4.17"),
        tradeoffs: ["Missing some v4 features", "But gains deployment flexibility"]
      }
    else
      # Business policy: If no cross-compilation needed, recommend v4
      %{
        recommended_version: "4.1.11",
        reason: "Latest features and performance",
        technical_basis: Core.in_production_support?("4.1.11"),
        tradeoffs: ["Host-only compilation", "But better performance and features"]
      }
    end

    IO.puts("Business recommendation based on user needs:")
    IO.puts("  - Version: #{recommendation.recommended_version}")
    IO.puts("  - Reason: #{recommendation.reason}")
    IO.puts("  - Technical basis: #{recommendation.technical_basis}")
    IO.puts("  - Tradeoffs: #{inspect(recommendation.tradeoffs)}")
    IO.puts("")

    IO.puts("Note: This business logic is SEPARATE from Core technical constraints.")
    IO.puts("Core only provides facts. Business layer makes decisions.")
  end

  @doc """
  Run all demonstrations
  """
  def run_all do
    demonstrate_technical_constraints()
    IO.puts("")
    demonstrate_cross_compilation_analysis()
    IO.puts("")
    demonstrate_technical_requirements()
    IO.puts("")
    demonstrate_business_logic_separation()
  end
end
