defmodule Defdo.TailwindBuilder.ConfigProviders.DevelopmentConfigProvider do
  @moduledoc """
  ConfigProvider optimized for development environments.
  
  Features:
  - More lenient version policies (allows experimental versions)
  - Faster timeout settings for development speed
  - Verbose logging and debugging enabled
  - More permissive plugin support
  - Local development optimizations
  """
  
  @behaviour Defdo.TailwindBuilder.ConfigProvider

  # Extended plugin support for development
  @development_supported_plugins %{
    "daisyui" => %{
      "version" => ~s["daisyui": "^4.12.23"],
      "statement" => ~s['daisyui': require('daisyui')],
      "description" => "Semantic component classes for Tailwind CSS",
      "npm_name" => "daisyui",
      "compatible_versions" => ["3.x", "4.x"]
    },
    "daisyui_v5" => %{
      "version" => ~s["daisyui": "^5.0.49"],
      "description" => "Semantic component classes for Tailwind CSS v5",
      "npm_name" => "daisyui", 
      "compatible_versions" => ["4.x"]
    },
    "@tailwindcss/typography" => %{
      "version" => ~s["@tailwindcss/typography": "^0.5.0"],
      "statement" => ~s['@tailwindcss/typography': require('@tailwindcss/typography')],
      "description" => "Beautiful typographic defaults for HTML",
      "npm_name" => "@tailwindcss/typography",
      "compatible_versions" => ["3.x", "4.x"]
    },
    "@tailwindcss/forms" => %{
      "version" => ~s["@tailwindcss/forms": "^0.5.0"],
      "statement" => ~s['@tailwindcss/forms': require('@tailwindcss/forms')],
      "description" => "Better default styles for form elements",
      "npm_name" => "@tailwindcss/forms",
      "compatible_versions" => ["3.x", "4.x"]
    },
    "tailwindcss-animate" => %{
      "version" => ~s["tailwindcss-animate": "^1.0.0"],
      "statement" => ~s['tailwindcss-animate': require('tailwindcss-animate')],
      "description" => "Animation utilities for Tailwind CSS",
      "npm_name" => "tailwindcss-animate",
      "compatible_versions" => ["3.x", "4.x"]
    }
  }

  # Development-friendly checksums (includes experimental versions)
  @development_checksums %{
    "3.4.17" => "89c0a7027449cbe564f8722e84108f7bfa0224b5d9289c47cc967ffef8e1b016",
    "4.0.9" => "7c36fdcdfed4d1b690a56a1267457a8ac9c640ccae2efcaed59f5053d330000a",
    "4.0.17" => "3590bcb90a75c32ba8b10d692d26838caedbc267a57db23931694abc9598c873",
    "4.1.11" => "149b7db8417a4a0419ada1d2dc428a11202fc6b971f037b7a8527371c59e0cae",
    # Development versions (for testing)
    "4.2.0-beta.1" => "dev_checksum_for_testing",
    "3.5.0-alpha.1" => "dev_checksum_for_testing"
  }

  @impl true
  def get_supported_plugins do
    # Allow environment override for development
    Application.get_env(:tailwind_builder, :development_plugins, @development_supported_plugins)
  end

  @impl true  
  def get_known_checksums do
    Application.get_env(:tailwind_builder, :development_checksums, @development_checksums)
  end

  @impl true
  def get_version_policy(version) do
    cond do
      # Allow all beta/alpha versions in development
      String.contains?(version, "beta") or String.contains?(version, "alpha") ->
        :allowed
      
      # Allow all stable versions with known checksums
      Map.has_key?(@development_checksums, version) ->
        :allowed
      
      # Even unknown versions are allowed in development for experimentation
      true ->
        :allowed
    end
  end

  @impl true
  def get_operation_limits do
    %{
      # Faster timeouts for development iteration
      download_timeout: 30_000,      # 30 seconds (faster than production)
      build_timeout: 120_000,        # 2 minutes (faster iteration)
      max_file_size: 200_000_000,    # 200MB (generous for development)
      max_concurrent_downloads: 5,   # Allow more concurrent operations
      retry_attempts: 2,             # Fewer retries for faster feedback
      cache_ttl: 300                 # 5 minutes cache (shorter for development)
    }
  end

  @impl true
  def get_deployment_config(target) do
    case target do
      :local ->
        %{
          destination: "/tmp/tailwind_dev_builds",
          cleanup_after: false,        # Keep files for debugging
          validate_binaries: false,    # Skip validation for speed
          generate_manifest: true
        }
      
      :test ->
        %{
          destination: "/tmp/tailwind_test_builds",
          cleanup_after: true,         # Clean up test files
          validate_binaries: false,    # Skip validation for speed
          generate_manifest: false     # Skip manifest for tests
        }
      
      :r2 ->
        %{
          bucket: "tailwind-dev-builds",
          prefix: "development/",
          public_access: true,         # Allow public access for dev sharing
          cache_control: "no-cache"    # No caching for development
        }
      
      :s3 ->
        %{
          bucket: "tailwind-development",
          prefix: "dev-builds/",
          storage_class: "STANDARD",
          public_access: true
        }
      
      _ ->
        %{
          destination: "/tmp/tailwind_unknown",
          cleanup_after: true,
          validate_binaries: false,
          generate_manifest: false
        }
    end
  end

  @impl true
  def get_build_policies do
    %{
      # Permissive build policies for development
      allow_experimental_features: true,
      skip_non_critical_validations: true,
      enable_debug_symbols: true,
      verbose_logging: true,
      parallel_builds: true,
      incremental_builds: true
    }
  end

  @impl true
  def get_deployment_policies do
    %{
      # Development deployment policies
      skip_production_checks: true,
      allow_overwrite: true,
      backup_existing: false,        # No backup needed in dev
      notify_on_deploy: false,       # No notifications for dev deploys
      auto_cleanup_old: true,        # Clean up old dev builds
      max_versions_kept: 5           # Keep only recent versions
    }
  end

  @impl true
  def validate_operation_policy(operation, context)

  def validate_operation_policy(:download, %{version: version}) do
    # Very permissive download policy for development
    case get_version_policy(version) do
      :allowed -> :ok
      _ -> :ok  # Allow everything in development
    end
  end

  def validate_operation_policy(:build, %{version: _version}) do
    # Always allow builds in development
    :ok
  end

  def validate_operation_policy(:deploy, %{target: target}) when target in [:local, :dev] do
    # Always allow local/dev deployments
    :ok
  end

  def validate_operation_policy(:deploy, %{target: target}) when target in [:r2, :s3] do
    # Allow cloud deployments but with warning
    {:warning, "Deploying to #{target} from development environment"}
  end

  def validate_operation_policy(:cross_compile, %{version: version}) do
    # Allow cross-compilation for all versions in development
    if String.starts_with?(version, "3.") do
      :ok
    else
      {:warning, "Cross-compilation may not work for #{version} but allowed in development"}
    end
  end

  def validate_operation_policy(_operation, _context) do
    # Default case: allow all other operations in development
    :ok
  end

  # Development-specific helpers

  @doc """
  Get development-specific logging configuration
  """
  def get_logging_config do
    %{
      level: :debug,
      enable_module_logging: true,
      log_http_requests: true,
      log_file_operations: true,
      log_compilation_steps: true,
      pretty_print: true
    }
  end

  @doc """
  Get development caching strategy
  """
  def get_cache_config do
    %{
      enable_disk_cache: true,
      cache_directory: "/tmp/tailwind_dev_cache",
      cache_downloads: true,
      cache_builds: false,         # Don't cache builds in development
      auto_invalidate: true,       # Auto-invalidate for fresh builds
      max_cache_size_mb: 1000     # 1GB cache for development
    }
  end

  @doc """
  Get development testing configuration
  """
  def get_testing_config do
    %{
      run_integration_tests: true,
      mock_external_services: false,  # Use real services in development
      parallel_test_execution: true,
      test_timeout_multiplier: 2.0,   # Longer timeouts for debugging
      preserve_test_artifacts: true   # Keep test files for inspection
    }
  end

  @doc """
  Check if running in development mode
  """
  def development_mode? do
    Mix.env() == :dev or Application.get_env(:tailwind_builder, :force_development_mode, false)
  end
end