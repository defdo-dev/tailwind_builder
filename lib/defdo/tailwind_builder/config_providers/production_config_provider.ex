defmodule Defdo.TailwindBuilder.ConfigProviders.ProductionConfigProvider do
  @moduledoc """
  ConfigProvider optimized for production environments.
  
  Features:
  - Strict version policies (only stable, tested versions)
  - Conservative timeout settings for reliability
  - Limited plugin support (only well-tested plugins)
  - Enhanced security and validation
  - Production-grade error handling
  """
  
  @behaviour Defdo.TailwindBuilder.ConfigProvider

  # Only stable, well-tested plugins for production
  @production_supported_plugins %{
    "daisyui" => %{
      "version" => ~s["daisyui": "^4.12.23"],
      "statement" => ~s['daisyui': require('daisyui')],
      "description" => "Semantic component classes for Tailwind CSS",
      "npm_name" => "daisyui",
      "compatible_versions" => ["3.x"]
    },
    "@tailwindcss/typography" => %{
      "version" => ~s["@tailwindcss/typography": "^0.5.0"],
      "statement" => ~s['@tailwindcss/typography': require('@tailwindcss/typography')],
      "description" => "Beautiful typographic defaults for HTML",
      "npm_name" => "@tailwindcss/typography",
      "compatible_versions" => ["3.x", "4.x"]
    }
  }

  # Only stable, verified checksums for production
  @production_checksums %{
    "3.4.17" => "89c0a7027449cbe564f8722e84108f7bfa0224b5d9289c47cc967ffef8e1b016",
    "4.0.17" => "3590bcb90a75c32ba8b10d692d26838caedbc267a57db23931694abc9598c873",
    "4.1.11" => "149b7db8417a4a0419ada1d2dc428a11202fc6b971f037b7a8527371c59e0cae"
  }

  # Blocked versions for production (security or stability issues)
  @blocked_versions [
    "4.0.9"    # Known issues with this version
  ]

  @impl true
  def get_supported_plugins do
    # Use only curated production plugins
    @production_supported_plugins
  end

  @impl true  
  def get_known_checksums do
    @production_checksums
  end

  @impl true
  def get_version_policy(version) do
    cond do
      # Block beta/alpha versions first (before other checks)
      String.contains?(version, "beta") or String.contains?(version, "alpha") or String.contains?(version, "rc") ->
        :blocked
      
      # Block known problematic versions
      version in @blocked_versions ->
        :blocked
      
      # Only allow versions with verified checksums
      Map.has_key?(@production_checksums, version) ->
        :allowed
      
      # Deprecate older stable versions
      String.starts_with?(version, "3.") ->
        :deprecated
      
      # Block everything else
      true ->
        :blocked
    end
  end

  @impl true
  def get_operation_limits do
    %{
      # Conservative timeouts for production reliability
      download_timeout: 120_000,      # 2 minutes
      build_timeout: 600_000,         # 10 minutes (allow for complex builds)
      max_file_size: 100_000_000,     # 100MB (strict limit)
      max_concurrent_downloads: 2,    # Conservative concurrency
      retry_attempts: 5,              # More retries for reliability
      cache_ttl: 3600                 # 1 hour cache (stable)
    }
  end

  @impl true
  def get_deployment_config(target) do
    case target do
      :r2 ->
        %{
          bucket: "tailwind-production",
          prefix: "releases/",
          public_access: false,        # Private by default
          cache_control: "public, max-age=31536000",  # 1 year cache
          encryption: "AES256",
          versioning: true,
          backup_retention_days: 90
        }
      
      :s3 ->
        %{
          bucket: "tailwind-prod-releases",
          prefix: "v1/",
          storage_class: "STANDARD_IA",  # Cost-optimized
          public_access: false,
          encryption: "aws:kms",
          lifecycle_policy: true,
          cloudfront_distribution: true
        }
      
      :cdn ->
        %{
          provider: "cloudflare",
          zone: "tailwind-releases",
          cache_everything: true,
          edge_cache_ttl: 86400,       # 24 hours
          browser_cache_ttl: 3600,     # 1 hour
          purge_on_deploy: true
        }
      
      _ ->
        %{
          destination: "/tmp/tailwind_unknown",
          cleanup_after: true,
          validate_binaries: true,
          generate_manifest: false
        }
    end
  end

  @impl true
  def get_build_policies do
    %{
      # Strict build policies for production
      allow_experimental_features: false,
      skip_non_critical_validations: false,
      enable_debug_symbols: false,
      verbose_logging: false,
      parallel_builds: false,          # Sequential for deterministic builds
      incremental_builds: false,       # Full builds for consistency
      checksum_validation: true,
      code_signing: true,
      virus_scanning: true
    }
  end

  @impl true
  def get_deployment_policies do
    %{
      # Production deployment policies
      skip_production_checks: false,
      allow_overwrite: false,         # Never overwrite in production
      backup_existing: true,          # Always backup
      notify_on_deploy: true,         # Alert on deployments
      auto_cleanup_old: false,        # Manual cleanup only
      max_versions_kept: 50,          # Keep many versions
      require_approval: true,         # Require deployment approval
      canary_deployment: true,        # Gradual rollout
      rollback_strategy: "immediate"  # Fast rollback capability
    }
  end

  @impl true
  def validate_operation_policy(operation, context)

  def validate_operation_policy(:download, %{version: version}) do
    case get_version_policy(version) do
      :allowed -> :ok
      :deprecated -> 
        {:warning, "Version #{version} is deprecated, consider upgrading"}
      :blocked -> 
        {:error, {:version_blocked, "Version #{version} is not allowed in production"}}
    end
  end

  def validate_operation_policy(:build, %{version: version}) do
    # Only allow builds for approved versions
    case get_version_policy(version) do
      :allowed -> :ok
      :deprecated -> 
        {:warning, "Building deprecated version #{version}"}
      :blocked -> 
        {:error, {:build_blocked, "Cannot build blocked version #{version}"}}
    end
  end

  def validate_operation_policy(:deploy, %{target: :local}) do
    {:error, {:deploy_blocked, "Local deployment not allowed in production"}}
  end

  def validate_operation_policy(:deploy, %{target: target}) when target in [:r2, :s3, :cdn] do
    # Check if deployment window is allowed
    if in_deployment_window?() do
      :ok
    else
      {:error, {:deploy_blocked, "Deployment outside allowed window"}}
    end
  end

  def validate_operation_policy(:cross_compile, %{version: version}) do
    # Only allow cross-compilation for v3 in production
    if String.starts_with?(version, "3.") do
      :ok
    else
      {:error, {:cross_compile_blocked, "Cross-compilation not supported for #{version} in production"}}
    end
  end

  def validate_operation_policy(_operation, _context) do
    # Default case: be restrictive in production
    {:error, {:operation_not_allowed, "Operation not explicitly allowed in production"}}
  end

  # Production-specific helpers

  @doc """
  Check if current time is within allowed deployment window
  """
  def in_deployment_window? do
    now = DateTime.utc_now()
    
    # Allow deployments Monday-Thursday, 9 AM - 5 PM UTC
    weekday = Date.day_of_week(DateTime.to_date(now))
    hour = now.hour
    
    weekday in [1, 2, 3, 4] and hour >= 9 and hour < 17
  end

  @doc """
  Get production logging configuration
  """
  def get_logging_config do
    %{
      level: :info,
      enable_module_logging: false,
      log_http_requests: false,      # Don't log requests in production
      log_file_operations: false,
      log_compilation_steps: false,
      pretty_print: false,
      structured_logging: true,      # JSON logs for production
      log_aggregation: true,
      retention_days: 30
    }
  end

  @doc """
  Get production monitoring configuration
  """
  def get_monitoring_config do
    %{
      enable_metrics: true,
      metrics_endpoint: "/metrics",
      health_check_endpoint: "/health",
      alert_on_errors: true,
      alert_on_slow_operations: true,
      performance_monitoring: true,
      error_tracking: "sentry",
      apm_service: "datadog"
    }
  end

  @doc """
  Get production security configuration
  """
  def get_security_config do
    %{
      validate_all_checksums: true,
      scan_for_vulnerabilities: true,
      enforce_https: true,
      validate_ssl_certificates: true,
      rate_limiting: %{
        enabled: true,
        requests_per_minute: 60,
        burst_limit: 10
      },
      ip_whitelisting: %{
        enabled: false,  # Configure as needed
        allowed_ips: []
      }
    }
  end

  @doc """
  Get production caching strategy
  """
  def get_cache_config do
    %{
      enable_disk_cache: true,
      cache_directory: "/var/cache/tailwind_builder",
      cache_downloads: true,
      cache_builds: true,           # Cache builds in production
      auto_invalidate: false,       # Manual cache invalidation
      max_cache_size_mb: 5000,      # 5GB cache for production
      cache_encryption: true,
      cache_compression: true
    }
  end

  @doc """
  Check if running in production mode
  """
  def production_mode? do
    Mix.env() == :prod or Application.get_env(:tailwind_builder, :force_production_mode, false)
  end

  @doc """
  Get production backup configuration
  """
  def get_backup_config do
    %{
      enable_automatic_backups: true,
      backup_schedule: "0 2 * * *",  # Daily at 2 AM
      backup_retention_days: 90,
      backup_storage: :s3,
      backup_encryption: true,
      backup_compression: true,
      backup_verification: true
    }
  end

  @doc """
  Get production telemetry configuration
  """
  def get_telemetry_config do
    %{
      enabled: true,
      level: :info,
      backends: [:console, :prometheus, :datadog],
      sample_rate: 0.1,  # Sample 10% in production for performance
      trace_retention_hours: 72,  # 3 days retention
      detailed_logging: false,
      performance_monitoring: true,
      error_tracking: :sentry,
      alert_on_errors: true,
      alert_on_high_latency: true,
      metrics_collection: %{
        system_metrics: true,
        business_metrics: true,
        performance_metrics: true,
        sla_metrics: true
      },
      dashboards: %{
        operations_dashboard: true,
        error_dashboard: true,
        performance_dashboard: true
      }
    }
  end
end