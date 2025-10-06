# API Reference

Complete API reference for TailwindBuilder's modular architecture.

## Table of Contents

- [Core Module](#core-module)
- [Downloader Module](#downloader-module)
- [Builder Module](#builder-module)
- [Deployer Module](#deployer-module)
- [Orchestrator Module](#orchestrator-module)
- [Telemetry Module](#telemetry-module)
- [Metrics Module](#metrics-module)
- [Dashboard Module](#dashboard-module)
- [Configuration Modules](#configuration-modules)
- [Utility Modules](#utility-modules)

## Core Module

**Module**: `Defdo.TailwindBuilder`

Main entry point for the TailwindBuilder system.

### Functions

#### `build_and_deploy/1`

Build and deploy TailwindCSS with plugins.

```elixir
@spec build_and_deploy(keyword()) :: {:ok, term()} | {:error, term()}
```

**Parameters:**
- `opts` (keyword): Configuration options

**Options:**
- `:version` (string, required): TailwindCSS version to build
- `:plugins` (list, optional): List of plugin names to include
- `:target` (atom, optional): Deployment target (`:local`, `:s3`, `:r2`, `:cdn`)
- `:output_dir` (string, optional): Output directory for local builds
- `:config_provider` (module, optional): Custom configuration provider
- `:telemetry_enabled` (boolean, optional): Enable telemetry tracking

**Examples:**

```elixir
# Basic usage
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui"],
  target: :local,
  output_dir: "./dist"
])

# With custom configuration
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui", "@tailwindcss/typography"],
  target: :s3,
  bucket: "my-assets",
  config_provider: MyApp.CustomConfigProvider
])
```

**Returns:**
- `{:ok, result}`: Success with build/deployment details
- `{:error, reason}`: Failure with error details

## Downloader Module

**Module**: `Defdo.TailwindBuilder.Downloader`

Handles TailwindCSS version downloads with validation.

### Functions

#### `download_and_extract/1`

Download and extract a specific TailwindCSS version.

```elixir
@spec download_and_extract(keyword()) :: {:ok, String.t()} | {:error, term()}
```

**Parameters:**
- `opts` (keyword): Download options

**Options:**
- `:version` (string, required): TailwindCSS version
- `:output_dir` (string, required): Directory to extract to
- `:checksum_validation` (boolean, optional): Enable checksum validation (default: true)
- `:force_download` (boolean, optional): Force re-download if exists (default: false)

**Example:**

```elixir
{:ok, extracted_path} = Defdo.TailwindBuilder.Downloader.download_and_extract([
  version: "4.1.11",
  output_dir: "/tmp/tailwind",
  checksum_validation: true
])
```

#### `validate_version/1`

Validate if a TailwindCSS version exists and is downloadable.

```elixir
@spec validate_version(String.t()) :: {:ok, map()} | {:error, term()}
```

**Example:**

```elixir
{:ok, version_info} = Defdo.TailwindBuilder.Downloader.validate_version("4.1.11")
# Returns: %{version: "4.1.11", size: 1234567, checksum: "abc123..."}
```

#### `get_download_url/1`

Get the download URL for a specific version.

```elixir
@spec get_download_url(String.t()) :: String.t()
```

## Builder Module

**Module**: `Defdo.TailwindBuilder.Builder`

Handles plugin application and asset compilation.

### Functions

#### `apply_plugins/1`

Apply plugins to a TailwindCSS installation.

```elixir
@spec apply_plugins(keyword()) :: {:ok, String.t()} | {:error, term()}
```

**Parameters:**
- `opts` (keyword): Build options

**Options:**
- `:source_dir` (string, required): Source directory with TailwindCSS
- `:plugins` (list, required): List of plugins to apply
- `:output_dir` (string, required): Output directory for built assets
- `:optimization_level` (atom, optional): `:fast`, `:balanced`, or `:maximum`

**Example:**

```elixir
{:ok, build_path} = Defdo.TailwindBuilder.Builder.apply_plugins([
  source_dir: "/tmp/tailwind/4.1.11",
  plugins: ["daisyui", "@tailwindcss/typography"],
  output_dir: "/tmp/build",
  optimization_level: :maximum
])
```

#### `validate_plugins/2`

Validate plugin compatibility with a TailwindCSS version.

```elixir
@spec validate_plugins(list(), String.t()) :: {:ok, list()} | {:error, term()}
```

**Example:**

```elixir
{:ok, validated_plugins} = Defdo.TailwindBuilder.Builder.validate_plugins(
  ["daisyui", "@tailwindcss/typography"],
  "4.1.11"
)
```

## Deployer Module

**Module**: `Defdo.TailwindBuilder.Deployer`

Handles deployment to various targets.

### Functions

#### `deploy/1`

Deploy built assets to a target.

```elixir
@spec deploy(keyword()) :: {:ok, list()} | {:error, term()}
```

**Parameters:**
- `opts` (keyword): Deployment options

**Common Options:**
- `:source_dir` (string, required): Directory with built assets
- `:target` (atom, required): Deployment target

**Target-Specific Options:**

**Local (`:local`):**
- `:output_dir` (string): Local output directory

**S3 (`:s3`):**
- `:bucket` (string): S3 bucket name
- `:region` (string): AWS region
- `:prefix` (string, optional): Key prefix
- `:public_read` (boolean, optional): Make files publicly readable

**R2 (`:r2`):**
- `:bucket` (string): R2 bucket name
- `:account_id` (string): Cloudflare account ID
- `:prefix` (string, optional): Key prefix

**CDN (`:cdn`):**
- `:distribution_id` (string): CloudFront distribution ID
- `:invalidation_paths` (list, optional): Paths to invalidate

**Examples:**

```elixir
# Local deployment
{:ok, files} = Defdo.TailwindBuilder.Deployer.deploy([
  source_dir: "/tmp/build",
  target: :local,
  output_dir: "./dist/css"
])

# S3 deployment
{:ok, files} = Defdo.TailwindBuilder.Deployer.deploy([
  source_dir: "/tmp/build",
  target: :s3,
  bucket: "my-assets",
  region: "us-east-1",
  prefix: "css/",
  public_read: true
])

# R2 deployment
{:ok, files} = Defdo.TailwindBuilder.Deployer.deploy([
  source_dir: "/tmp/build",
  target: :r2,
  bucket: "my-r2-bucket",
  account_id: "your-account-id"
])
```

#### `validate_config/1`

Validate deployment configuration.

```elixir
@spec validate_config(map()) :: {:ok, :valid} | {:error, term()}
```

## Orchestrator Module

**Module**: `Defdo.TailwindBuilder.Orchestrator`

Manages complex workflows and task coordination.

### Functions

#### `execute_workflow/1`

Execute a complex multi-step workflow.

```elixir
@spec execute_workflow(keyword()) :: {:ok, term()} | {:error, term()}
```

**Parameters:**
- `opts` (keyword): Workflow options

**Options:**
- `:steps` (list, required): List of workflow steps
- `:version` (string, required): TailwindCSS version
- `:plugins` (list, optional): Plugins to apply
- `:targets` (list, optional): Multiple deployment targets
- `:parallel` (boolean, optional): Execute steps in parallel where possible

**Example:**

```elixir
{:ok, results} = Defdo.TailwindBuilder.Orchestrator.execute_workflow([
  version: "4.1.11",
  plugins: ["daisyui"],
  steps: [:download, :build, :deploy],
  targets: [:local, :s3],
  parallel: true
])
```

## Telemetry Module

**Module**: `Defdo.TailwindBuilder.Telemetry`

Real-time monitoring and observability.

### Functions

#### `start_link/1`

Start the telemetry system.

```elixir
@spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
```

#### `start_span/2`

Start a new operation span.

```elixir
@spec start_span(atom(), map()) :: String.t()
```

**Parameters:**
- `operation` (atom): Operation type (`:download`, `:build`, `:deploy`)
- `metadata` (map): Initial span metadata

**Example:**

```elixir
span_id = Defdo.TailwindBuilder.Telemetry.start_span(:download, %{
  version: "4.1.11",
  size: 1024
})
```

#### `end_span/3`

End an operation span.

```elixir
@spec end_span(String.t(), atom(), map()) :: :ok
```

**Parameters:**
- `span_id` (string): Span identifier
- `status` (atom): Final status (`:success`, `:error`, `:timeout`)
- `metadata` (map): Final span metadata

#### `track_event/3`

Track an event within an operation.

```elixir
@spec track_event(atom(), atom(), map()) :: :ok
```

**Example:**

```elixir
Defdo.TailwindBuilder.Telemetry.track_event(:download, :progress, %{
  percent: 50,
  bytes_downloaded: 512
})
```

#### `track_download/2`, `track_build/3`, `track_deploy/2`

Convenience functions for automatic span management.

```elixir
@spec track_download(String.t(), function()) :: term()
@spec track_build(String.t(), list(), function()) :: term()
@spec track_deploy(atom(), function()) :: term()
```

**Examples:**

```elixir
result = Defdo.TailwindBuilder.Telemetry.track_download("4.1.11", fn ->
  # Download logic here
  {:ok, "Downloaded successfully"}
end)

result = Defdo.TailwindBuilder.Telemetry.track_build("4.1.11", ["daisyui"], fn ->
  # Build logic here
  {:ok, "Built successfully"}
end)
```

#### `get_stats/0`

Get current telemetry statistics.

```elixir
@spec get_stats() :: map()
```

#### `get_active_spans/0`

Get currently active spans.

```elixir
@spec get_active_spans() :: list()
```

## Metrics Module

**Module**: `Defdo.TailwindBuilder.Metrics`

Specialized metrics collection and reporting.

### Functions

#### `record_download_metrics/4`

Record download operation metrics.

```elixir
@spec record_download_metrics(String.t(), integer(), integer(), atom()) :: :ok
```

**Parameters:**
- `version` (string): TailwindCSS version
- `size_bytes` (integer): Download size in bytes
- `duration_ms` (integer): Duration in milliseconds
- `status` (atom): Operation status

#### `record_build_metrics/5`

Record build operation metrics.

```elixir
@spec record_build_metrics(String.t(), list(), integer(), integer(), atom()) :: :ok
```

#### `record_deployment_metrics/5`

Record deployment operation metrics.

```elixir
@spec record_deployment_metrics(atom(), integer(), integer(), integer(), atom()) :: :ok
```

#### `record_resource_metrics/0`

Record system resource metrics.

```elixir
@spec record_resource_metrics() :: :ok
```

#### `get_metrics_summary/1`

Get comprehensive metrics summary.

```elixir
@spec get_metrics_summary(integer()) :: map()
```

## Dashboard Module

**Module**: `Defdo.TailwindBuilder.Dashboard`

Real-time monitoring dashboard.

### Functions

#### `generate_summary/1`

Generate dashboard summary in various formats.

```elixir
@spec generate_summary(keyword()) :: String.t() | map()
```

**Options:**
- `:format` (atom): Output format (`:text`, `:json`, `:html`, `:raw`)
- `:time_window_minutes` (integer): Time window for metrics (default: 60)

**Examples:**

```elixir
# Text dashboard
text = Defdo.TailwindBuilder.Dashboard.generate_summary(format: :text)

# JSON dashboard
json = Defdo.TailwindBuilder.Dashboard.generate_summary(format: :json)

# HTML dashboard
html = Defdo.TailwindBuilder.Dashboard.generate_summary(format: :html)

# Raw data
data = Defdo.TailwindBuilder.Dashboard.generate_summary(format: :raw)
```

#### `display_live_dashboard/1`

Display live auto-refreshing dashboard in terminal.

```elixir
@spec display_live_dashboard(integer()) :: no_return()
```

**Parameters:**
- `refresh_seconds` (integer): Refresh interval in seconds

#### `export_dashboard/2`

Export dashboard to file.

```elixir
@spec export_dashboard(String.t(), atom()) :: :ok | {:error, term()}
```

## Configuration Modules

### ConfigProvider Behaviour

**Module**: `Defdo.TailwindBuilder.ConfigProvider`

Defines the configuration provider interface.

#### Callbacks

```elixir
@callback get_security_policies() :: map()
@callback get_timeout_config() :: map()
@callback get_build_policies() :: map()
@callback get_deployment_policies() :: map()
@callback get_telemetry_config() :: map()
```

### ConfigProviderFactory

**Module**: `Defdo.TailwindBuilder.ConfigProviderFactory`

Factory for automatic provider selection.

#### Functions

#### `get_provider/0`

Get configuration provider for current environment.

```elixir
@spec get_provider() :: module()
```

#### `get_provider/1`

Get configuration provider for specific environment.

```elixir
@spec get_provider(atom()) :: module()
```

**Example:**

```elixir
# Automatic selection based on Mix.env()
provider = Defdo.TailwindBuilder.ConfigProviderFactory.get_provider()

# Explicit environment
dev_provider = Defdo.TailwindBuilder.ConfigProviderFactory.get_provider(:dev)
prod_provider = Defdo.TailwindBuilder.ConfigProviderFactory.get_provider(:prod)
```

## Utility Modules

### VersionFetcher

**Module**: `Defdo.TailwindBuilder.VersionFetcher`

Utility for fetching available TailwindCSS versions.

#### Functions

#### `fetch_available_versions/0`

Fetch list of available TailwindCSS versions.

```elixir
@spec fetch_available_versions() :: list(String.t())
```

#### `get_latest_version/0`

Get the latest available version.

```elixir
@spec get_latest_version() :: String.t()
```

### PluginManager

**Module**: `Defdo.TailwindBuilder.PluginManager`

Plugin management and validation utilities.

#### Functions

#### `plugin_supported?/2`

Check if a plugin is supported for a specific version.

```elixir
@spec plugin_supported?(String.t(), String.t()) :: boolean()
```

#### `get_plugin_info/1`

Get information about a specific plugin.

```elixir
@spec get_plugin_info(String.t()) :: map() | nil
```

### Dependencies

**Module**: `Defdo.TailwindBuilder.Dependencies`

System dependency checking utilities.

#### Functions

#### `check_system_dependencies/0`

Check if all required system dependencies are available.

```elixir
@spec check_system_dependencies() :: map()
```

**Returns:**

```elixir
%{
  node: boolean(),
  rust: boolean(),
  git: boolean(),
  npm: boolean()
}
```

## Error Types

Common error types returned by the API:

```elixir
# Download errors
{:error, :version_not_found}
{:error, :download_failed}
{:error, :checksum_mismatch}
{:error, :extraction_failed}

# Build errors
{:error, :plugin_not_supported}
{:error, :build_failed}
{:error, :optimization_failed}

# Deployment errors
{:error, :invalid_target}
{:error, :missing_credentials}
{:error, :upload_failed}
{:error, :permission_denied}

# Configuration errors
{:error, :invalid_config}
{:error, :missing_required_option}
{:error, :timeout}
```

## Type Specifications

Common types used throughout the API:

```elixir
@type version() :: String.t()
@type plugin() :: String.t()
@type target() :: :local | :s3 | :r2 | :cdn
@type status() :: :success | :error | :timeout
@type span_id() :: String.t()
@type config_opts() :: keyword()
@type result() :: {:ok, term()} | {:error, term()}
```

## Best Practices

1. **Error Handling**: Always pattern match on return values
2. **Telemetry**: Enable telemetry for production monitoring
3. **Configuration**: Use appropriate config providers for each environment
4. **Validation**: Validate inputs before processing
5. **Timeouts**: Set appropriate timeouts for your environment
6. **Logging**: Use structured logging for debugging
7. **Testing**: Mock external dependencies in tests

## Examples

### Complete Workflow

```elixir
defmodule MyApp.TailwindPipeline do
  alias Defdo.TailwindBuilder

  def build_and_deploy_all(version, plugins) do
    # Start telemetry
    {:ok, _} = TailwindBuilder.Telemetry.start_link([])
    
    # Build for multiple environments
    environments = [
      {:dev, :local, "./dev-assets"},
      {:staging, :s3, "staging-bucket"},
      {:prod, :s3, "prod-bucket"}
    ]
    
    results = Enum.map(environments, fn {env, target, location} ->
      config_provider = get_provider_for_env(env)
      
      opts = [
        version: version,
        plugins: plugins,
        target: target,
        config_provider: config_provider
      ]
      
      opts = case target do
        :local -> [{:output_dir, location} | opts]
        :s3 -> [{:bucket, location} | opts]
        _ -> opts
      end
      
      case TailwindBuilder.build_and_deploy(opts) do
        {:ok, result} -> 
          IO.puts("✅ #{env}: Success")
          {:ok, env, result}
        {:error, reason} -> 
          IO.puts("❌ #{env}: #{inspect(reason)}")
          {:error, env, reason}
      end
    end)
    
    # Generate final report
    successes = Enum.count(results, fn {status, _, _} -> status == :ok end)
    total = length(results)
    
    IO.puts("\n📊 Pipeline Results: #{successes}/#{total} successful")
    
    results
  end
  
  defp get_provider_for_env(:dev), do: TailwindBuilder.ConfigProviders.DevelopmentConfigProvider
  defp get_provider_for_env(:staging), do: TailwindBuilder.ConfigProviders.StagingConfigProvider
  defp get_provider_for_env(:prod), do: TailwindBuilder.ConfigProviders.ProductionConfigProvider
end
```

---

This API reference provides comprehensive documentation for all modules in the TailwindBuilder system. For interactive examples, see the included LiveBook notebook.