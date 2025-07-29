defmodule Defdo.TailwindBuilder.Core.Capabilities do
  @moduledoc """
  Core technical capabilities and constraints for different Tailwind CSS versions.
  
  This module defines the technical limitations and compilation capabilities 
  for each major Tailwind version without business logic or configuration.
  
  Technical Facts:
  - Tailwind v3: npm-based compilation, supports cross-compilation for all architectures
  - Tailwind v4: Rust-based compilation, no cross-compilation support (host-only)
  """

  @doc """
  Technical constraints matrix for Tailwind versions
  """
  def get_version_constraints(version) when is_binary(version) do
    case get_major_version(version) do
      :v3 -> v3_constraints()
      :v4 -> v4_constraints()
      :unknown -> unknown_version_constraints()
    end
  end

  @doc """
  Get supported target architectures for a given version
  """
  def get_supported_architectures(version) when is_binary(version) do
    constraints = get_version_constraints(version)
    constraints.supported_architectures
  end

  @doc """
  Check if version supports cross-compilation
  """
  def supports_cross_compilation?(version) when is_binary(version) do
    constraints = get_version_constraints(version)
    constraints.cross_compilation
  end

  @doc """
  Get compilation method for version
  """
  def get_compilation_method(version) when is_binary(version) do
    constraints = get_version_constraints(version)
    constraints.compilation_method
  end

  @doc """
  Get required build tools for version
  """
  def get_required_tools(version) when is_binary(version) do
    constraints = get_version_constraints(version)
    constraints.required_tools
  end

  @doc """
  Get runtime environment constraints
  """
  def get_runtime_constraints(version) when is_binary(version) do
    constraints = get_version_constraints(version)
    constraints.runtime_constraints
  end

  @doc """
  Check if version is in production support
  """
  def in_production_support?(version) when is_binary(version) do
    case get_major_version(version) do
      :v3 -> true
      :v4 -> true
      :unknown -> false
    end
  end

  # Private functions

  defp get_major_version(version) do
    try do
      case Version.compare(version, "4.0.0") do
        :lt -> :v3
        :eq -> :v4
        :gt -> :v4
      end
    rescue
      Version.InvalidVersionError -> :unknown
    end
  end

  defp v3_constraints do
    %{
      major_version: :v3,
      compilation_method: :npm,
      cross_compilation: true,
      supported_architectures: [
        "linux-x64", "linux-arm64", 
        "darwin-x64", "darwin-arm64", 
        "win32-x64", "win32-arm64",
        "freebsd-x64"
      ],
      required_tools: ["npm", "node"],
      optional_tools: ["pnpm", "yarn"],
      runtime_constraints: %{
        node_version: ">= 14.0.0",
        npm_version: ">= 6.0.0"
      },
      file_structure: %{
        base_path: "standalone-cli",
        config_files: ["package.json", "standalone.js"],
        build_commands: ["npm install", "npm run build"]
      },
      plugin_system: %{
        dependency_section: "devDependencies",
        requires_bundling: true,
        supports_dynamic_import: false
      }
    }
  end

  defp v4_constraints do
    %{
      major_version: :v4,
      compilation_method: :rust,
      cross_compilation: false,
      supported_architectures: [:host_only],
      required_tools: ["pnpm", "node"],
      optional_tools: ["npm", "yarn"],
      runtime_constraints: %{
        node_version: ">= 18.0.0",
        pnpm_version: ">= 8.0.0",
        rust_toolchain: "stable"
      },
      file_structure: %{
        base_path: "packages/@tailwindcss-standalone",
        config_files: ["package.json", "src/index.ts"],
        build_commands: ["pnpm install --no-frozen-lockfile", "pnpm run build"]
      },
      plugin_system: %{
        dependency_section: "dependencies",
        requires_bundling: true,
        supports_dynamic_import: true
      }
    }
  end

  defp unknown_version_constraints do
    %{
      major_version: :unknown,
      compilation_method: :unknown,
      cross_compilation: false,
      supported_architectures: [],
      required_tools: [],
      optional_tools: [],
      runtime_constraints: %{},
      file_structure: %{},
      plugin_system: %{}
    }
  end
end