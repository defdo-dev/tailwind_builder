defmodule Defdo.TailwindBuilder.Core do
  @moduledoc """
  Core API that exposes technical limitations and capabilities.
  
  This is the main interface for querying technical constraints without
  business logic. Upper layers can use this API to make informed decisions
  about what operations are technically possible.
  
  ## Usage Examples
  
      # Check if cross-compilation is technically possible
      iex> Core.can_cross_compile?("4.1.11", "linux-x64")
      false
      
      # Get technical requirements for compilation
      iex> Core.get_compilation_requirements("3.4.17")
      %{required_tools: ["npm", "node"], ...}
      
      # Check architecture compatibility
      iex> Core.get_supported_architectures("4.0.9")
      [:host_only]
  """

  alias Defdo.TailwindBuilder.Core.Capabilities
  alias Defdo.TailwindBuilder.Core.ArchitectureMatrix
  alias Defdo.TailwindBuilder.Core.TechnicalConstraints

  # Version and capability queries

  @doc """
  Check if a version is technically supported
  """
  defdelegate in_production_support?(version), to: Capabilities

  @doc """
  Get all technical constraints for a version
  """
  defdelegate get_version_constraints(version), to: Capabilities

  @doc """
  Get compilation method (npm, rust, etc.)
  """
  defdelegate get_compilation_method(version), to: Capabilities

  @doc """
  Get required build tools
  """
  defdelegate get_required_tools(version), to: Capabilities

  @doc """
  Get runtime environment constraints
  """
  defdelegate get_runtime_constraints(version), to: Capabilities

  # Architecture and cross-compilation queries

  @doc """
  Check if cross-compilation is supported for version
  """
  defdelegate supports_cross_compilation?(version), to: Capabilities

  @doc """
  Get supported target architectures
  """
  defdelegate get_supported_architectures(version), to: Capabilities

  @doc """
  Check if we can compile for a specific target architecture
  """
  defdelegate can_compile_for_target?(version, target_arch), to: ArchitectureMatrix

  @doc """
  Get list of architectures that can be compiled from current host
  """
  defdelegate get_available_targets(version), to: ArchitectureMatrix

  @doc """
  Get current host system architecture
  """
  defdelegate get_host_architecture(), to: ArchitectureMatrix

  @doc """
  Get detailed compilation capabilities
  """
  defdelegate get_compilation_details(version), to: ArchitectureMatrix

  @doc """
  Get full compatibility matrix for all versions
  """
  defdelegate get_compatibility_matrix(), to: ArchitectureMatrix

  # Technical feasibility validation

  @doc """
  Check if an operation is technically possible
  """
  defdelegate is_technically_possible?(operation, params), to: TechnicalConstraints

  @doc """
  Get technical requirements for an operation
  """
  defdelegate get_technical_requirements(operation, params), to: TechnicalConstraints

  @doc """
  Get all technical limitations for a version
  """
  defdelegate get_technical_limitations(version), to: TechnicalConstraints

  @doc """
  Validate technical feasibility of a request
  """
  defdelegate validate_technical_feasibility(request), to: TechnicalConstraints

  # Convenience functions for common queries

  @doc """
  Quick check: can we cross-compile from current host to target?
  """
  def can_cross_compile?(version, target_arch) do
    supports_cross_compilation?(version) and 
    can_compile_for_target?(version, target_arch)
  end

  @doc """
  Quick check: what's the best package manager for this version?
  """
  def get_preferred_package_manager(version) do
    constraints = get_version_constraints(version)
    List.first(constraints.required_tools) || "npm"
  end

  @doc """
  Quick check: can we compile this version on current system?
  """
  def can_compile_on_current_system?(version) do
    case validate_technical_feasibility(%{
      version: version,
      target_arch: get_host_architecture(),
      plugins: []
    }) do
      {:ok, :technically_feasible} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get summary of what's possible with a version
  """
  def get_version_summary(version) do
    constraints = get_version_constraints(version)
    compilation_details = get_compilation_details(version)
    
    %{
      version: version,
      compilation_method: constraints.compilation_method,
      cross_compilation: constraints.cross_compilation,
      supported_architectures: length(constraints.supported_architectures),
      can_compile_from_current_host: can_compile_on_current_system?(version),
      available_targets_from_host: length(get_available_targets(version)),
      required_tools: constraints.required_tools,
      limitations: compilation_details.limitations
    }
  end

  @doc """
  Compare technical capabilities between versions
  """
  def compare_versions(version1, version2) do
    summary1 = get_version_summary(version1)
    summary2 = get_version_summary(version2)
    
    %{
      version1: summary1,
      version2: summary2,
      differences: %{
        compilation_method: summary1.compilation_method != summary2.compilation_method,
        cross_compilation: summary1.cross_compilation != summary2.cross_compilation,
        architecture_support: summary1.supported_architectures != summary2.supported_architectures,
        tool_requirements: summary1.required_tools != summary2.required_tools
      }
    }
  end

  @doc """
  Get architecture support matrix for all supported architectures
  """
  def get_architecture_support_matrix do
    %{
      :"linux-x64" => %{
        supported_versions: ["3.4.17", "4.0.9", "4.1.11"],
        compilation_method: :npm,
        cross_compilation_available: true
      },
      :"linux-arm64" => %{
        supported_versions: ["3.4.17", "4.0.9", "4.1.11"],
        compilation_method: :npm,
        cross_compilation_available: true
      },
      :"darwin-x64" => %{
        supported_versions: ["3.4.17", "4.0.9", "4.1.11"],
        compilation_method: :npm,
        cross_compilation_available: true
      },
      :"darwin-arm64" => %{
        supported_versions: ["3.4.17", "4.0.9", "4.1.11"],
        compilation_method: :npm,
        cross_compilation_available: true
      },
      :"win32-x64" => %{
        supported_versions: ["3.4.17"],
        compilation_method: :npm,
        cross_compilation_available: true
      },
      :"freebsd-x64" => %{
        supported_versions: ["3.4.17"],
        compilation_method: :npm,
        cross_compilation_available: true
      }
    }
  end

  @doc """
  Analyze extracted Tailwind CSS structure and validate it
  """
  def analyze_extracted_structure(extraction_path, version) do
    constraints = get_version_constraints(version)
    
    case constraints.major_version do
      :v3 ->
        standalone_path = Path.join(extraction_path, "standalone-cli")
        package_json_path = Path.join(standalone_path, "package.json")
        
        %{
          version: version,
          major_version: :v3,
          valid_structure: File.exists?(standalone_path) && File.exists?(package_json_path),
          standalone_path: standalone_path,
          package_json_exists: File.exists?(package_json_path),
          structure_type: "standalone-cli"
        }
        
      :v4 ->
        packages_path = Path.join([extraction_path, "packages", "@tailwindcss-standalone"])
        package_json_path = Path.join(packages_path, "package.json")
        
        %{
          version: version,
          major_version: :v4,
          valid_structure: File.exists?(packages_path) && File.exists?(package_json_path),
          standalone_path: packages_path,
          package_json_exists: File.exists?(package_json_path),
          structure_type: "packages/@tailwindcss-standalone"
        }
        
      _ ->
        %{
          version: version,
          major_version: constraints.major_version,
          valid_structure: false,
          standalone_path: nil,
          package_json_exists: false,
          structure_type: "unsupported"
        }
    end
  end
end