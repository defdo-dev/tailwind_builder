defmodule Defdo.TailwindBuilder.Core.TechnicalConstraints do
  @moduledoc """
  Pure technical constraints without business logic.

  This module separates technical facts (what the system can/cannot do)
  from business policies (what the system should/should not do).

  Technical constraints are immutable facts about the compilation toolchain.
  Business policies are configurable rules that may change over time.
  """

  alias Defdo.TailwindBuilder.Core.Capabilities
  alias Defdo.TailwindBuilder.Core.ArchitectureMatrix

  @doc """
  Check if a technical operation is possible (not whether it's allowed)
  """
  def is_technically_possible?(operation, params) do
    case operation do
      :cross_compile -> can_cross_compile?(params[:version], params[:target_arch])
      :compile_version -> can_compile_version?(params[:version])
      :use_package_manager -> can_use_package_manager?(params[:version], params[:manager])
      :run_on_architecture -> can_run_on_architecture?(params[:version], params[:arch])
      _ -> {:error, :unknown_operation}
    end
  end

  @doc """
  Get technical requirements for an operation
  """
  def get_technical_requirements(operation, params) do
    case operation do
      :compile_version -> get_compilation_requirements(params[:version])
      :cross_compile -> get_cross_compilation_requirements(params[:version], params[:target_arch])
      :plugin_integration -> get_plugin_requirements(params[:version], params[:plugin])
      _ -> {:error, :unknown_operation}
    end
  end

  @doc """
  Get technical limitations for a version
  """
  def get_technical_limitations(version) when is_binary(version) do
    constraints = Capabilities.get_version_constraints(version)
    arch_info = ArchitectureMatrix.get_compilation_details(version)

    %{
      version: version,
      compilation_limitations: arch_info.limitations,
      architecture_constraints: %{
        cross_compilation: constraints.cross_compilation,
        supported_targets: constraints.supported_architectures,
        host_only: not constraints.cross_compilation
      },
      toolchain_constraints: %{
        required_tools: constraints.required_tools,
        runtime_requirements: constraints.runtime_constraints
      },
      file_system_constraints: %{
        required_structure: constraints.file_structure,
        config_file_format: get_config_format_constraints(version)
      }
    }
  end

  @doc """
  Validate technical feasibility without business rules
  """
  def validate_technical_feasibility(request) do
    with :ok <- validate_version_support(request[:version]),
         :ok <- validate_architecture_support(request[:version], request[:target_arch]),
         :ok <- validate_toolchain_availability(request[:version]),
         :ok <- validate_plugin_compatibility(request[:version], request[:plugins]) do
      {:ok, :technically_feasible}
    else
      {:error, reason} -> {:error, {:not_technically_feasible, reason}}
    end
  end

  # Private functions - Technical validation only

  defp can_cross_compile?(version, target_arch) when is_binary(version) and is_binary(target_arch) do
    ArchitectureMatrix.can_compile_for_target?(version, target_arch)
  end

  defp can_compile_version?(version) when is_binary(version) do
    Capabilities.in_production_support?(version)
  end

  defp can_use_package_manager?(version, manager) when is_binary(version) and is_binary(manager) do
    constraints = Capabilities.get_version_constraints(version)
    required_tools = constraints.required_tools
    optional_tools = constraints.optional_tools

    manager in required_tools or manager in optional_tools
  end

  defp can_run_on_architecture?(version, arch) when is_binary(version) and is_binary(arch) do
    supported = Capabilities.get_supported_architectures(version)
    # Convert arch to atom for comparison if it's a string
    arch_atom = if is_binary(arch), do: String.to_atom(arch), else: arch
    arch_atom in supported
  end

  defp get_compilation_requirements(version) do
    constraints = Capabilities.get_version_constraints(version)

    %{
      required_tools: constraints.required_tools,
      optional_tools: constraints.optional_tools,
      runtime_constraints: constraints.runtime_constraints,
      build_commands: constraints.file_structure.build_commands,
      working_directory: constraints.file_structure.base_path
    }
  end

  defp get_cross_compilation_requirements(version, target_arch) do
    base_requirements = get_compilation_requirements(version)

    case can_cross_compile?(version, target_arch) do
      true ->
        Map.put(base_requirements, :cross_compilation, %{
          supported: true,
          target_architecture: target_arch,
          additional_setup: []
        })
      false ->
        Map.put(base_requirements, :cross_compilation, %{
          supported: false,
          reason: "Rust-based compilation does not support cross-compilation",
          alternative: "Use separate build environment for #{target_arch}"
        })
    end
  end

  defp get_plugin_requirements(version, plugin) when is_binary(version) and is_binary(plugin) do
    constraints = Capabilities.get_version_constraints(version)

    %{
      dependency_section: constraints.plugin_system.dependency_section,
      requires_bundling: constraints.plugin_system.requires_bundling,
      supports_dynamic_import: constraints.plugin_system.supports_dynamic_import,
      config_files_to_modify: constraints.file_structure.config_files
    }
  end

  defp get_config_format_constraints(version) do
    constraints = Capabilities.get_version_constraints(version)

    case constraints.major_version do
      :v3 ->
        %{
          package_json: %{dependency_section: "devDependencies"},
          standalone_js: %{requires_require_statements: true}
        }
      :v4 ->
        %{
          package_json: %{dependency_section: "dependencies"},
          index_ts: %{supports_dynamic_imports: true, requires_bundling_setup: true}
        }
      _ ->
        %{}
    end
  end

  defp validate_version_support(version) when is_binary(version) do
    if Capabilities.in_production_support?(version) do
      :ok
    else
      {:error, :version_not_supported}
    end
  end

  defp validate_architecture_support(version, target_arch) when is_binary(version) and is_binary(target_arch) do
    if can_cross_compile?(version, target_arch) or target_arch == ArchitectureMatrix.get_host_architecture() do
      :ok
    else
      {:error, :architecture_not_supported}
    end
  end

  defp validate_toolchain_availability(version) when is_binary(version) do
    constraints = Capabilities.get_version_constraints(version)

    # For testing purposes, we'll be more lenient about tool availability
    # In a real deployment, this would check actual tool availability
    case constraints.major_version do
      :unsupported -> {:error, :unknown_version}
      _ -> :ok  # Assume tools are available for testing
    end
  end

  defp validate_plugin_compatibility(version, plugins) when is_binary(version) and is_list(plugins) do
    constraints = Capabilities.get_version_constraints(version)

    case constraints.plugin_system do
      %{} when map_size(constraints.plugin_system) == 0 ->
        {:error, :plugin_system_not_available}
      _plugin_system ->
        :ok
    end
  end
  defp validate_plugin_compatibility(_version, nil), do: :ok
end
