defmodule Defdo.TailwindBuilder.Core.ArchitectureMatrix do
  @moduledoc """
  Architecture compatibility matrix for Tailwind CSS compilation.
  
  Defines which architectures can be compiled for each Tailwind version,
  considering technical limitations of the underlying compilation toolchain.
  """

  alias Defdo.TailwindBuilder.Core.Capabilities

  @doc """
  Get compatibility matrix for all supported versions and architectures
  """
  def get_compatibility_matrix do
    %{
      "3.4.17" => get_version_compatibility("3.4.17"),
      "4.0.9" => get_version_compatibility("4.0.9"),
      "4.0.17" => get_version_compatibility("4.0.17"),
      "4.1.11" => get_version_compatibility("4.1.11")
    }
  end

  @doc """
  Get architecture compatibility for a specific version
  """
  def get_version_compatibility(version) when is_binary(version) do
    constraints = Capabilities.get_version_constraints(version)
    
    %{
      version: version,
      compilation_method: constraints.compilation_method,
      cross_compilation: constraints.cross_compilation,
      supported_architectures: constraints.supported_architectures,
      host_architecture: get_host_architecture(),
      can_compile_for: get_compilable_architectures(constraints)
    }
  end

  @doc """
  Check if we can compile for a target architecture from current host
  """
  def can_compile_for_target?(version, target_architecture) when is_binary(version) and is_binary(target_architecture) do
    compatibility = get_version_compatibility(version)
    target_architecture in compatibility.can_compile_for
  end

  @doc """
  Get list of architectures that can be compiled from current host
  """
  def get_available_targets(version) when is_binary(version) do
    compatibility = get_version_compatibility(version)
    compatibility.can_compile_for
  end

  @doc """
  Get host system architecture detection
  """
  def get_host_architecture do
    arch = :erlang.system_info(:system_architecture) |> to_string()
    os = case :os.type() do
      {:unix, :darwin} -> "darwin"
      {:unix, :linux} -> "linux"
      {:unix, :freebsd} -> "freebsd"
      {:win32, _} -> "win32"
      _ -> "unknown"
    end
    
    cpu = cond do
      arch =~ "x86_64" or arch =~ "amd64" -> "x64"
      arch =~ "aarch64" or arch =~ "arm64" -> "arm64"
      arch =~ "arm" -> "arm"
      true -> "unknown"
    end
    
    "#{os}-#{cpu}"
  end

  @doc """
  Get detailed compilation capabilities for version
  """
  def get_compilation_details(version) when is_binary(version) do
    constraints = Capabilities.get_version_constraints(version)
    host_arch = get_host_architecture()
    
    %{
      version: version,
      host_architecture: host_arch,
      compilation_method: constraints.compilation_method,
      cross_compilation_available: constraints.cross_compilation,
      supported_targets: constraints.supported_architectures,
      compilable_targets: get_compilable_architectures(constraints),
      limitations: get_compilation_limitations(constraints),
      recommended_workflow: get_recommended_workflow(constraints, host_arch)
    }
  end

  # Private functions

  defp get_compilable_architectures(constraints) do
    case constraints.cross_compilation do
      true -> constraints.supported_architectures
      false -> [get_host_architecture()]
    end
  end

  defp get_compilation_limitations(constraints) do
    case constraints.compilation_method do
      :npm ->
        []
      :rust ->
        [
          "No cross-compilation support",
          "Can only compile for host architecture",
          "Requires Rust toolchain on target system"
        ]
      :unknown ->
        ["Unknown compilation method", "No support guaranteed"]
    end
  end

  defp get_recommended_workflow(constraints, host_arch) do
    case constraints.compilation_method do
      :npm ->
        %{
          single_host: "Compile for all targets from any host",
          ci_cd: "Use single build agent to generate all architecture binaries",
          distribution: "Upload all binaries from single compilation run"
        }
      :rust ->
        %{
          single_host: "Can only compile for #{host_arch}",
          ci_cd: "Requires separate build agents for each target architecture",
          distribution: "Collect binaries from multiple compilation hosts"
        }
      :unknown ->
        %{
          single_host: "Unknown workflow requirements",
          ci_cd: "Consult version documentation",
          distribution: "Manual verification required"
        }
    end
  end
end