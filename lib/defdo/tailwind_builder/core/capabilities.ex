defmodule Defdo.TailwindBuilder.Core.Capabilities do
  @moduledoc """
  Core technical capabilities and constraints for different Tailwind CSS versions.

  This module defines the technical limitations and compilation capabilities
  for each major Tailwind version without business logic or configuration.

  Technical Facts:
  - Tailwind v3: npm-based compilation, supports cross-compilation for all architectures
  - Tailwind v4: Rust/Cargo-based compilation with full cross-compilation support
  - Tailwind v5+: Future-proofed architecture detection
  """

  @doc """
  Technical constraints matrix for Tailwind versions
  """
  def get_version_constraints(version) when is_binary(version) do
    case get_major_version(version) do
      :v3 -> v3_constraints()
      :v4 -> v4_constraints()
      :v5 -> v5_constraints()
      :v6 -> v6_constraints()
      :unsupported -> unsupported_version_constraints()
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
      :v5 -> false  # Future version - not yet in production
      :v6 -> false  # Future version - not yet in production
      :unsupported -> false
    end
  end

  # Private functions

  defp get_major_version(version) do
    try do
      # Check for obviously invalid versions first
      if String.starts_with?(version, "999.") do
        :unsupported
      else
        case version do
          # Parse major version number more precisely
          "3" <> _ -> :v3
          "4" <> _ -> :v4
          "5" <> _ -> :v5  # Future v5 support
          "6" <> _ -> :v6  # Future v6 support
          _ ->
            # Fallback to semantic comparison for more complex version strings
            case Version.compare(version, "4.0.0") do
              :lt -> :v3
              _ ->
                case Version.compare(version, "5.0.0") do
                  :lt -> :v4
                  _ ->
                    case Version.compare(version, "6.0.0") do
                      :lt -> :v5
                      _ -> :v6  # Assume v6+ uses similar pattern to v4-v5
                    end
                end
            end
        end
      end
    rescue
      Version.InvalidVersionError -> :unsupported
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
      compilation_method: :pnpm_workspace,
      cross_compilation: true,
      supported_architectures: [
        :"x86_64-unknown-linux-gnu",
        :"x86_64-unknown-linux-musl",
        :"aarch64-unknown-linux-gnu",
        :"aarch64-unknown-linux-musl",
        :"armv7-unknown-linux-gnueabihf",
        :"armv7-unknown-linux-musleabihf",
        :"x86_64-pc-windows-msvc",
        :"aarch64-pc-windows-msvc",
        :"x86_64-apple-darwin",
        :"aarch64-apple-darwin",
        :"x86_64-unknown-freebsd",
        :"aarch64-linux-android",
        :"armv7-linux-androideabi"
      ],
      required_tools: ["pnpm", "node", "cargo", "rustc"],
      optional_tools: ["strip"],
      runtime_constraints: %{
        node_version: ">= 20.0.0",
        pnpm_version: ">= 8.0.0",
        rust_version: ">= 1.70.0"
      },
      file_structure: %{
        base_path: ".",
        config_files: ["package.json", "pnpm-workspace.yaml", "Cargo.toml"],
        build_commands: [
          "pnpm install --ignore-scripts --filter=!./playgrounds/*",
          "pnpm run --filter ./crates/node build:platform"
        ]
      },
      plugin_system: %{
        dependency_section: "dependencies",
        requires_bundling: true,
        supports_dynamic_import: true,
        plugin_integration: "package_json"
      },
      binary_output: %{
        target_dir: "packages/@tailwindcss-standalone/dist",
        binary_name: "tailwindcss-macos-arm64",
        strip_symbols: true,
        generate_checksums: true
      }
    }
  end

  defp v5_constraints do
    # Future v5 - assume similar to v4 but with potential improvements
    %{
      major_version: :v5,
      compilation_method: :cargo,
      cross_compilation: true,
      supported_architectures: [
        :"x86_64-unknown-linux-gnu",
        :"x86_64-unknown-linux-musl",
        :"aarch64-unknown-linux-gnu",
        :"aarch64-unknown-linux-musl",
        :"armv7-unknown-linux-gnueabihf",
        :"armv7-unknown-linux-musleabihf",
        :"x86_64-pc-windows-msvc",
        :"aarch64-pc-windows-msvc",
        :"x86_64-apple-darwin",
        :"aarch64-apple-darwin",
        :"x86_64-unknown-freebsd",
        :"aarch64-linux-android",
        :"armv7-linux-androideabi",
        # Potential new architectures in v5
        :"riscv64gc-unknown-linux-gnu",
        :"wasm32-unknown-unknown"
      ],
      required_tools: ["cargo", "rustc"],
      optional_tools: ["node", "pnpm", "strip"],
      runtime_constraints: %{
        rust_version: ">= 1.75.0",  # Potentially newer Rust requirement
        cargo_version: ">= 1.75.0"
      },
      file_structure: %{
        base_path: ".",
        config_files: ["Cargo.toml", "Cargo.lock"],
        build_commands: ["cargo build --release"]
      },
      plugin_system: %{
        dependency_section: "dependencies",
        requires_bundling: false,
        supports_dynamic_import: false,
        plugin_integration: "rust_crate"
      },
      binary_output: %{
        target_dir: "target/release",
        binary_name: "tailwindcss",
        strip_symbols: true,
        generate_checksums: true
      }
    }
  end

  defp v6_constraints do
    # Future v6 - assume continued Rust evolution with enhanced features
    %{
      major_version: :v6,
      compilation_method: :cargo,
      cross_compilation: true,
      supported_architectures: [
        :"x86_64-unknown-linux-gnu",
        :"x86_64-unknown-linux-musl",
        :"aarch64-unknown-linux-gnu",
        :"aarch64-unknown-linux-musl",
        :"armv7-unknown-linux-gnueabihf",
        :"armv7-unknown-linux-musleabihf",
        :"x86_64-pc-windows-msvc",
        :"aarch64-pc-windows-msvc",
        :"x86_64-apple-darwin",
        :"aarch64-apple-darwin",
        :"x86_64-unknown-freebsd",
        :"aarch64-linux-android",
        :"armv7-linux-androideabi",
        :"riscv64gc-unknown-linux-gnu",
        :"wasm32-unknown-unknown",
        # Potential newer architectures
        :"loongarch64-unknown-linux-gnu"
      ],
      required_tools: ["cargo", "rustc"],
      optional_tools: ["node", "pnpm", "strip"],
      runtime_constraints: %{
        rust_version: ">= 1.80.0",  # Future Rust requirement
        cargo_version: ">= 1.80.0"
      },
      file_structure: %{
        base_path: ".",
        config_files: ["Cargo.toml", "Cargo.lock"],
        build_commands: ["cargo build --release"]
      },
      plugin_system: %{
        dependency_section: "dependencies",
        requires_bundling: false,
        supports_dynamic_import: false,
        plugin_integration: "rust_crate"
      },
      binary_output: %{
        target_dir: "target/release",
        binary_name: "tailwindcss",
        strip_symbols: true,
        generate_checksums: true
      }
    }
  end

  defp unsupported_version_constraints do
    %{
      major_version: :unsupported,
      compilation_method: :unsupported,
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