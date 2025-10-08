defmodule Defdo.TailwindBuilder.ConfigProviders.StagingConfigProvider do
  @moduledoc """
  ConfigProvider optimized for staging/pre-production environments.

  Features:
  - Production-like settings with some flexibility for testing
  - Moderate security policies
  - Performance monitoring and debugging capabilities
  - Safe environment for testing production features
  - Rollback and recovery features
  """

  @behaviour Defdo.TailwindBuilder.ConfigProvider

  # Staging supports more plugins than production but less than development
  @staging_supported_plugins %{
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
    }
  }

  # Staging checksums (includes release candidates for testing)
  @staging_checksums %{
    "3.4.17" => "89c0a7027449cbe564f8722e84108f7bfa0224b5d9289c47cc967ffef8e1b016",
    "4.0.9" => "7c36fdcdfed4d1b690a56a1267457a8ac9c640ccae2efcaed59f5053d330000a",
    "4.0.17" => "3590bcb90a75c32ba8b10d692d26838caedbc267a57db23931694abc9598c873",
    "4.1.11" => "149b7db8417a4a0419ada1d2dc428a11202fc6b971f037b7a8527371c59e0cae",
    # Release candidates for staging testing
    "4.2.0-rc.1" => "rc_checksum_for_staging_testing"
  }

  @impl true
  def get_supported_plugins do
    # Allow some customization for staging experiments
    Application.get_env(:tailwind_builder, :staging_plugins, @staging_supported_plugins)
  end

  @impl true
  def get_known_checksums do
    Application.get_env(:tailwind_builder, :staging_checksums, @staging_checksums)
  end

  @impl true
  def get_version_policy(version) do
    cond do
      # Allow release candidates in staging
      String.contains?(version, "-rc.") ->
        :allowed

      # Allow all stable versions with known checksums
      Map.has_key?(@staging_checksums, version) ->
        :allowed

      # Deprecate very old versions
      version in ["3.0.0", "3.1.0", "3.2.0"] ->
        :deprecated

      # Block unknown versions (more restrictive than development)
      true ->
        :blocked
    end
  end

  @impl true
  def get_operation_limits do
    %{
      # Production-like timeouts but slightly more generous
      # 1.5 minutes
      download_timeout: 90_000,
      # 5 minutes
      build_timeout: 300_000,
      # 150MB (between dev and prod)
      max_file_size: 150_000_000,
      # Moderate concurrency
      max_concurrent_downloads: 3,
      # Balanced retry strategy
      retry_attempts: 3,
      # 30 minutes cache
      cache_ttl: 1800
    }
  end

  @impl true
  def get_deployment_config(target) do
    case target do
      :staging ->
        %{
          destination: "/var/www/tailwind-staging",
          cleanup_after: false,
          validate_binaries: true,
          generate_manifest: true,
          backup_before_deploy: true,
          rollback_capability: true
        }

      :r2 ->
        %{
          bucket: "tailwind-staging",
          prefix: "staging/",
          # Allow public access for testing
          public_access: true,
          # 1 hour cache
          cache_control: "public, max-age=3600",
          encryption: "AES256",
          versioning: true,
          backup_retention_days: 30
        }

      :s3 ->
        %{
          bucket: "tailwind-staging-releases",
          prefix: "staging/",
          storage_class: "STANDARD",
          public_access: true,
          encryption: "aws:kms",
          # No lifecycle in staging
          lifecycle_policy: false,
          cloudfront_distribution: false
        }

      :preview ->
        %{
          provider: "vercel",
          auto_deploy: true,
          preview_urls: true,
          share_with_team: true,
          # Auto-cleanup preview deployments
          ephemeral: true
        }

      _ ->
        %{
          destination: "/tmp/tailwind_staging_unknown",
          cleanup_after: true,
          validate_binaries: true,
          generate_manifest: false
        }
    end
  end

  @impl true
  def get_build_policies do
    %{
      # Staging build policies (production-like with some flexibility)
      allow_experimental_features: false,
      skip_non_critical_validations: false,
      # Enable for debugging
      enable_debug_symbols: true,
      # More verbose for issue diagnosis
      verbose_logging: true,
      # Enable for performance
      parallel_builds: true,
      # Full builds for consistency
      incremental_builds: false,
      checksum_validation: true,
      # Not required in staging
      code_signing: false,
      # Skip for speed
      virus_scanning: false
    }
  end

  @impl true
  def get_deployment_policies do
    %{
      # Staging deployment policies
      skip_production_checks: false,
      # Allow overwriting for testing
      allow_overwrite: true,
      # Always backup
      backup_existing: true,
      # Alert on deployments
      notify_on_deploy: true,
      # Cleanup old versions
      auto_cleanup_old: true,
      # Keep moderate number of versions
      max_versions_kept: 10,
      # No approval required
      require_approval: false,
      # Direct deployment in staging
      canary_deployment: false,
      # Manual rollback
      rollback_strategy: "manual"
    }
  end

  @impl true
  def validate_operation_policy(operation, context)

  def validate_operation_policy(:download, %{version: version}) do
    case get_version_policy(version) do
      :allowed ->
        :ok

      :deprecated ->
        {:warning, "Version #{version} is deprecated, consider upgrading"}

      :blocked ->
        {:error, {:version_blocked, "Version #{version} is not allowed in staging"}}
    end
  end

  def validate_operation_policy(:build, %{version: version}) do
    case get_version_policy(version) do
      :allowed ->
        :ok

      :deprecated ->
        {:warning, "Building deprecated version #{version} in staging"}

      :blocked ->
        {:error, {:build_blocked, "Cannot build blocked version #{version} in staging"}}
    end
  end

  def validate_operation_policy(:deploy, %{target: :local}) do
    {:warning, "Local deployment in staging environment"}
  end

  def validate_operation_policy(:deploy, %{target: target}) when target in [:staging, :preview] do
    # Always allow staging deployments
    :ok
  end

  def validate_operation_policy(:deploy, %{target: target}) when target in [:r2, :s3] do
    # Check business hours for cloud deployments (more lenient than production)
    if in_allowed_deployment_hours?() do
      :ok
    else
      {:warning, "Deploying outside recommended hours"}
    end
  end

  def validate_operation_policy(:cross_compile, %{version: version}) do
    # Allow cross-compilation for v3, warn for v4
    if String.starts_with?(version, "3.") do
      :ok
    else
      {:warning, "Cross-compilation may not work reliably for #{version} in staging"}
    end
  end

  def validate_operation_policy(_operation, _context) do
    # Default case: allow with warning in staging
    {:warning, "Operation allowed in staging but may need review"}
  end

  # Staging-specific helpers

  @doc """
  Check if current time is within recommended deployment hours (more lenient than production)
  """
  def in_allowed_deployment_hours? do
    now = DateTime.utc_now()

    # Allow deployments Monday-Friday, 8 AM - 8 PM UTC (longer window than production)
    weekday = Date.day_of_week(DateTime.to_date(now))
    hour = now.hour

    weekday in [1, 2, 3, 4, 5] and hour >= 8 and hour < 20
  end

  @doc """
  Get staging logging configuration
  """
  def get_logging_config do
    %{
      level: :info,
      # Enable for debugging
      enable_module_logging: true,
      # Log for troubleshooting
      log_http_requests: true,
      log_file_operations: true,
      log_compilation_steps: true,
      # Human-readable logs
      pretty_print: true,
      # Keep simple for staging
      structured_logging: false,
      log_aggregation: false,
      # Shorter retention than production
      retention_days: 7
    }
  end

  @doc """
  Get staging monitoring configuration
  """
  def get_monitoring_config do
    %{
      enable_metrics: true,
      metrics_endpoint: "/metrics",
      health_check_endpoint: "/health",
      alert_on_errors: true,
      # Less strict than production
      alert_on_slow_operations: false,
      performance_monitoring: true,
      # Use dev error tracking
      error_tracking: "development",
      # No APM in staging
      apm_service: nil
    }
  end

  @doc """
  Get staging testing configuration
  """
  def get_testing_config do
    %{
      run_integration_tests: true,
      # Test performance in staging
      run_performance_tests: true,
      # Skip security tests for speed
      run_security_tests: false,
      # Use production-like data
      test_with_real_data: true,
      # Run load tests
      load_testing: true,
      # Skip chaos testing
      chaos_testing: false,
      # Enable UAT in staging
      user_acceptance_testing: true
    }
  end

  @doc """
  Get staging caching configuration
  """
  def get_cache_config do
    %{
      enable_disk_cache: true,
      cache_directory: "/var/cache/tailwind_staging",
      cache_downloads: true,
      cache_builds: true,
      # Manual invalidation
      auto_invalidate: false,
      # 2GB cache
      max_cache_size_mb: 2000,
      # No encryption needed
      cache_encryption: false,
      cache_compression: true
    }
  end

  @doc """
  Get staging feature flags configuration
  """
  def get_feature_flags do
    %{
      # Feature flags for testing new features in staging
      enable_new_plugin_system:
        Application.get_env(:tailwind_builder, :enable_new_plugin_system, false),
      enable_experimental_compression:
        Application.get_env(:tailwind_builder, :enable_experimental_compression, false),
      enable_advanced_caching:
        Application.get_env(:tailwind_builder, :enable_advanced_caching, true),
      enable_parallel_processing:
        Application.get_env(:tailwind_builder, :enable_parallel_processing, true)
    }
  end

  @doc """
  Check if running in staging mode
  """
  def staging_mode? do
    Mix.env() == :staging or Application.get_env(:tailwind_builder, :force_staging_mode, false)
  end

  @doc """
  Get staging database configuration
  """
  def get_database_config do
    %{
      # Use copy of production data
      use_production_data_copy: true,
      # Anonymize for privacy
      anonymize_sensitive_data: true,
      # Refresh data periodically
      auto_refresh_data: true,
      # Backup before destructive tests
      backup_before_tests: true,
      # Clean up after tests
      cleanup_test_data: true
    }
  end

  @doc """
  Get staging notification configuration
  """
  def get_notification_config do
    %{
      notify_on_deploy: true,
      notify_on_errors: true,
      notify_on_performance_issues: false,
      notification_channels: [:slack, :email],
      # Lower threshold than production
      notification_threshold: :warning,
      rate_limit_notifications: true
    }
  end

  @doc """
  Get staging telemetry configuration
  """
  def get_telemetry_config do
    %{
      enabled: true,
      level: :info,
      backends: [:console, :prometheus],
      # Sample 50% in staging
      sample_rate: 0.5,
      # 1 day retention
      trace_retention_hours: 24,
      detailed_logging: true,
      performance_monitoring: true,
      error_tracking: :development,
      alert_on_errors: true,
      # Less strict than production
      alert_on_high_latency: false,
      metrics_collection: %{
        system_metrics: true,
        business_metrics: true,
        performance_metrics: true,
        feature_flag_metrics: true
      },
      testing_integration: %{
        load_testing_metrics: true,
        performance_testing_metrics: true,
        user_acceptance_metrics: true
      }
    }
  end
end
