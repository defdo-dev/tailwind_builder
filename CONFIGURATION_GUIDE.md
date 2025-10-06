# Configuration Guide

This guide covers all configuration options available in TailwindBuilder's modular architecture.

## Table of Contents

- [Overview](#overview)
- [Environment-Specific Providers](#environment-specific-providers)
- [Configuration Options](#configuration-options)
- [Custom Configuration](#custom-configuration)
- [Deployment Configuration](#deployment-configuration)
- [Telemetry Configuration](#telemetry-configuration)
- [Examples](#examples)

## Overview

TailwindBuilder uses a **ConfigProvider** pattern that allows environment-specific configurations. Each environment (development, production, staging, testing) has its own optimized settings.

## Environment-Specific Providers

### DevelopmentConfigProvider

Optimized for development workflow with fast iterations:

```elixir
# Automatic selection in dev environment
provider = Defdo.TailwindBuilder.ConfigProviders.DevelopmentConfigProvider

# Key characteristics:
# - Fast timeouts for quick feedback
# - Permissive plugin policies
# - Extensive logging
# - Local deployment preferred
```

**Configuration highlights:**
- Download timeout: 30 seconds
- Build timeout: 2 minutes
- Debug symbols: Enabled
- Verbose logging: Enabled
- Parallel builds: Enabled

### ProductionConfigProvider

Strict, secure configuration for production environments:

```elixir
provider = Defdo.TailwindBuilder.ConfigProviders.ProductionConfigProvider

# Key characteristics:
# - Conservative timeouts for reliability
# - Strict security policies
# - Comprehensive validation
# - Optimized builds
```

**Configuration highlights:**
- Download timeout: 5 minutes
- Build timeout: 10 minutes
- Debug symbols: Disabled
- Verbose logging: Disabled
- Backup existing: Required

### StagingConfigProvider

Balanced configuration for staging environments:

```elixir
provider = Defdo.TailwindBuilder.ConfigProviders.StagingConfigProvider

# Key characteristics:
# - Production-like but more forgiving
# - Good for testing deployment pipelines
# - Balanced performance vs safety
```

### TestingConfigProvider

Optimized for automated testing:

```elixir
provider = Defdo.TailwindBuilder.ConfigProviders.TestingConfigProvider

# Key characteristics:
# - Very fast timeouts
# - Mock-friendly settings
# - Minimal validation for speed
# - In-memory operations when possible
```

## Configuration Options

### Operation Limits

```elixir
operation_limits = provider.get_operation_limits()

# Available options:
%{
  download_timeout: integer(),        # milliseconds
  build_timeout: integer(),          # milliseconds  
  max_file_size: integer(),          # bytes
  max_concurrent_downloads: integer(),
  retry_attempts: integer(),
  cache_ttl: integer()              # seconds
}
```

### Build Policies

```elixir
build_policies = provider.get_build_policies()

# Available options:
%{
  allow_experimental_features: boolean(),
  skip_non_critical_validations: boolean(),
  enable_debug_symbols: boolean(),
  verbose_logging: boolean(),
  parallel_builds: boolean(),
  incremental_builds: boolean()
}
```

### Deployment Policies

```elixir
deployment_policies = provider.get_deployment_policies()

# Available options:
%{
  skip_production_checks: boolean(),
  allow_overwrite: boolean(),
  backup_existing: boolean(),
  notify_on_deploy: boolean(),
  auto_cleanup_old: boolean(),
  max_versions_kept: integer()
}
```

### Telemetry Configuration

```elixir
telemetry_config = provider.get_telemetry_config()

# Available options:
%{
  enabled: boolean(),
  level: :debug | :info | :warn | :error,
  backends: [atom()],
  sample_rate: float(),
  trace_retention_hours: integer(),
  detailed_logging: boolean(),
  performance_monitoring: boolean(),
  alert_on_errors: boolean(),
  alert_on_high_latency: boolean()
}
```

## Custom Configuration

### Creating a Custom Provider

```elixir
defmodule MyApp.CustomConfigProvider do
  @behaviour Defdo.TailwindBuilder.ConfigProvider
  
  @impl true
  def get_supported_plugins do
    %{
      "daisyui" => %{
        "version" => ~s["daisyui": "^4.12.23"], 
        "statement" => ~s['daisyui': require('daisyui')],
        "description" => "Semantic component classes for Tailwind CSS"
      }
    }
  end
  
  @impl true
  def get_operation_limits do
    %{
      download_timeout: 60_000,
      build_timeout: 300_000,
      max_file_size: 100_000_000,
      max_concurrent_downloads: 3,
      retry_attempts: 3,
      cache_ttl: 3600
    }
  end
  
  @impl true
  def get_build_policies do
    %{
      allow_experimental_features: false,
      skip_non_critical_validations: false,
      enable_debug_symbols: false,
      verbose_logging: false,
      parallel_builds: true,
      incremental_builds: true
    }
  end
  
  @impl true
  def get_deployment_policies do
    %{
      skip_production_checks: false,
      allow_overwrite: false,
      backup_existing: true,
      notify_on_deploy: true,
      auto_cleanup_old: false,
      max_versions_kept: 10
    }
  end
  
  @impl true
  def get_telemetry_config do
    %{
      enabled: true,
      level: :info,
      backends: [:console, :file],
      sample_rate: 0.1,
      trace_retention_hours: 24,
      detailed_logging: false,
      performance_monitoring: true,
      alert_on_errors: true,
      alert_on_high_latency: false
    }
  end
end
```

### Using Custom Provider

```elixir
# Use custom provider explicitly
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui"],
  target: :s3,
  config_provider: MyApp.CustomConfigProvider
])
```

## Deployment Configuration

### S3 Configuration

```elixir
s3_config = %{
  target: :s3,
  bucket: "my-tailwind-assets",
  region: "us-east-1",
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  prefix: "tailwind/",
  public_read: true,
  cache_control: "public, max-age=31536000"
}
```

### R2 Configuration (Cloudflare)

```elixir
r2_config = %{
  target: :r2,
  bucket: "my-r2-bucket",
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
  prefix: "css/",
  public_read: true
}
```

### CDN Configuration

```elixir
cdn_config = %{
  target: :cdn,
  distribution_id: "E1234567890ABC",
  origin_bucket: "my-origin-bucket",
  invalidation_paths: ["/*"],
  cache_behaviors: %{
    "*.css" => %{ttl: 31536000}
  }
}
```

### Local Configuration

```elixir
local_config = %{
  target: :local,
  output_dir: "./dist/css",
  create_directories: true,
  overwrite_existing: true,
  preserve_structure: true
}
```

## Telemetry Configuration

### Backend Configuration

#### Console Backend
```elixir
telemetry_config = %{
  backends: [:console],
  level: :info,
  detailed_logging: true
}
```

#### Prometheus Backend
```elixir
telemetry_config = %{
  backends: [:console, :prometheus],
  prometheus: %{
    endpoint: "/metrics",
    registry: :default
  }
}
```

#### DataDog Backend
```elixir
telemetry_config = %{
  backends: [:console, :datadog],
  datadog: %{
    api_key: System.get_env("DATADOG_API_KEY"),
    tags: ["env:production", "service:tailwind-builder"]
  }
}
```

### Sampling Configuration

```elixir
# Development: Sample everything
telemetry_config = %{sample_rate: 1.0}

# Production: Sample 10% for performance
telemetry_config = %{sample_rate: 0.1}

# High-traffic: Sample 1%
telemetry_config = %{sample_rate: 0.01}
```

## Examples

### Development Setup

```elixir
# Fast development builds
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui"],
  target: :local,
  output_dir: "./dev-assets",
  config_provider: Defdo.TailwindBuilder.ConfigProviders.DevelopmentConfigProvider
])
```

### Production Deployment

```elixir
# Secure production build with full validation
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui", "@tailwindcss/typography"],
  target: :s3,
  bucket: "prod-assets",
  config_provider: Defdo.TailwindBuilder.ConfigProviders.ProductionConfigProvider
])
```

### Testing Configuration

```elixir
# Fast tests with minimal validation
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui"],
  target: :local,
  output_dir: "/tmp/test-build",
  config_provider: Defdo.TailwindBuilder.ConfigProviders.TestingConfigProvider
])
```

### Multi-Environment Pipeline

```elixir
defmodule MyApp.BuildPipeline do
  def deploy_to_environment(env, version, plugins) do
    provider = case env do
      :dev -> Defdo.TailwindBuilder.ConfigProviders.DevelopmentConfigProvider
      :staging -> Defdo.TailwindBuilder.ConfigProviders.StagingConfigProvider
      :prod -> Defdo.TailwindBuilder.ConfigProviders.ProductionConfigProvider
    end
    
    target_config = get_target_config(env)
    
    Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      config_provider: provider
    ] ++ target_config)
  end
  
  defp get_target_config(:dev), do: [target: :local, output_dir: "./dev-assets"]
  defp get_target_config(:staging), do: [target: :s3, bucket: "staging-assets"]
  defp get_target_config(:prod), do: [target: :s3, bucket: "prod-assets"]
end
```

### Configuration Validation

```elixir
# Validate configuration before use
defmodule ConfigValidator do
  def validate_provider(provider) do
    with {:ok, _} <- validate_security_policies(provider.get_security_policies()),
         {:ok, _} <- validate_timeout_config(provider.get_timeout_config()),
         {:ok, _} <- validate_build_policies(provider.get_build_policies()) do
      {:ok, :valid}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_security_policies(policies) do
    cond do
      policies.max_download_size_mb > 1000 ->
        {:error, "Download size limit too high"}
      length(policies.allowed_domains) == 0 ->
        {:error, "No allowed domains specified"}
      true ->
        {:ok, :valid}
    end
  end
  
  # ... other validation functions
end
```

## Environment Variables

Common environment variables used across configurations:

```bash
# AWS/S3 Configuration
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"

# Cloudflare R2 Configuration
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export R2_ACCESS_KEY_ID="your-r2-access-key"
export R2_SECRET_ACCESS_KEY="your-r2-secret-key"

# Telemetry Configuration
export DATADOG_API_KEY="your-datadog-key"
export PROMETHEUS_ENDPOINT="http://localhost:9090"

# Build Configuration
export TAILWIND_OPTIMIZATION_LEVEL="maximum"
export TAILWIND_MAX_PLUGINS="5"
export TAILWIND_ENABLE_SOURCE_MAPS="false"
```

## Best Practices

1. **Environment Separation**: Use different providers for different environments
2. **Security First**: Always enable checksum validation in production
3. **Monitoring**: Enable telemetry in all environments
4. **Timeouts**: Set appropriate timeouts based on your infrastructure
5. **Validation**: Validate configurations before deployment
6. **Secrets Management**: Never hardcode credentials
7. **Performance**: Use appropriate sample rates for telemetry
8. **Testing**: Use fast configurations for CI/CD pipelines

## Troubleshooting

### Configuration Issues

```elixir
# Debug configuration
provider = MyApp.CustomConfigProvider
config = %{
  security: provider.get_security_policies(),
  timeouts: provider.get_timeout_config(),
  build: provider.get_build_policies(),
  deployment: provider.get_deployment_policies(),
  telemetry: provider.get_telemetry_config()
}

IO.inspect(config, label: "Full Configuration")
```

### Common Problems

1. **Timeout Issues**: Increase timeout values for slow networks
2. **Plugin Validation Failures**: Check `allowed_plugin_sources`
3. **Deployment Failures**: Verify credentials and permissions
4. **Telemetry Not Working**: Check if backends are properly configured
5. **Build Failures**: Verify plugin compatibility and build policies

---

This configuration guide covers all aspects of TailwindBuilder's flexible configuration system. For more examples, see the test suite and the included LiveBook notebook.