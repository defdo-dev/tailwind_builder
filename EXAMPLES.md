# TailwindBuilder Examples

Practical examples demonstrating TailwindBuilder's capabilities.

## Table of Contents

- [Basic Usage](#basic-usage)
- [Environment-Specific Builds](#environment-specific-builds)
- [Multi-Target Deployment](#multi-target-deployment)
- [Telemetry & Monitoring](#telemetry--monitoring)
- [Custom Configuration](#custom-configuration)
- [Error Handling](#error-handling)
- [Integration Examples](#integration-examples)

## Basic Usage

### Simple Build

```elixir
# Basic TailwindCSS build with DaisyUI
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui"],
  target: :local,
  output_dir: "./assets/css"
])

IO.inspect(result)
# {:ok, %{files: [...], duration_ms: 2341, ...}}
```

### Multiple Plugins

```elixir
# Build with multiple plugins
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11", 
  plugins: ["daisyui", "@tailwindcss/typography", "@tailwindcss/forms"],
  target: :local,
  output_dir: "./dist"
])
```

### Legacy API Usage

```elixir
# Using the original API (still supported)
alias Defdo.TailwindBuilder

# Download and extract
{:ok, _} = TailwindBuilder.download("/tmp/tailwind", "4.1.11")

# Add plugins
TailwindBuilder.add_plugin("daisyui", "4.1.11", "/tmp/tailwind")

# Build
{:ok, build_result} = TailwindBuilder.build("4.1.11", "/tmp/tailwind")
```

## Environment-Specific Builds

### Development Build

```elixir
defmodule MyApp.TailwindDev do
  def quick_build(version, plugins) do
    # Fast development build
    Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :local,
      output_dir: "./dev-assets",
      config_provider: Defdo.TailwindBuilder.ConfigProviders.DevelopmentConfigProvider
    ])
  end
end

# Usage
{:ok, result} = MyApp.TailwindDev.quick_build("4.1.11", ["daisyui"])
```

### Production Build

```elixir
defmodule MyApp.TailwindProd do
  def secure_build(version, plugins, bucket) do
    # Secure production build with full validation
    Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :s3,
      bucket: bucket,
      config_provider: Defdo.TailwindBuilder.ConfigProviders.ProductionConfigProvider
    ])
  end
end

# Usage
{:ok, result} = MyApp.TailwindProd.secure_build("4.1.11", ["daisyui"], "prod-assets")
```

### Testing Build

```elixir
defmodule MyApp.TailwindTest do
  def test_build do
    # Fast test build with minimal validation
    Defdo.TailwindBuilder.build_and_deploy([
      version: "4.1.11",
      plugins: ["daisyui"],
      target: :local,
      output_dir: "/tmp/test-tailwind",
      config_provider: Defdo.TailwindBuilder.ConfigProviders.TestingConfigProvider
    ])
  end
end
```

## Multi-Target Deployment

### Deploy to Multiple Targets

```elixir
defmodule MyApp.MultiDeploy do
  def deploy_everywhere(version, plugins) do
    targets = [
      {:local, "./dist"},
      {:s3, "staging-bucket"},
      {:s3, "prod-bucket"}
    ]
    
    results = Enum.map(targets, fn {target, location} ->
      opts = base_opts(version, plugins, target)
      opts = add_location(opts, target, location)
      
      case Defdo.TailwindBuilder.build_and_deploy(opts) do
        {:ok, result} -> 
          IO.puts("✅ #{target}: Success")
          {:ok, target, result}
        {:error, reason} -> 
          IO.puts("❌ #{target}: #{inspect(reason)}")
          {:error, target, reason}
      end
    end)
    
    successes = Enum.count(results, fn {status, _, _} -> status == :ok end)
    IO.puts("Deployed to #{successes}/#{length(targets)} targets")
    
    results
  end
  
  defp base_opts(version, plugins, target) do
    [version: version, plugins: plugins, target: target]
  end
  
  defp add_location(opts, :local, dir), do: [{:output_dir, dir} | opts]
  defp add_location(opts, :s3, bucket), do: [{:bucket, bucket} | opts]
  defp add_location(opts, _, _), do: opts
end

# Usage
results = MyApp.MultiDeploy.deploy_everywhere("4.1.11", ["daisyui"])
```

### Conditional Deployment

```elixir
defmodule MyApp.ConditionalDeploy do
  def deploy_based_on_env(version, plugins) do
    case Mix.env() do
      :dev -> 
        deploy_local(version, plugins)
      :test -> 
        deploy_test(version, plugins)
      :prod -> 
        deploy_production(version, plugins)
      _ -> 
        {:error, :unknown_environment}
    end
  end
  
  defp deploy_local(version, plugins) do
    Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :local,
      output_dir: "./dev-assets"
    ])
  end
  
  defp deploy_test(version, plugins) do
    Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :local,
      output_dir: "/tmp/test-assets"
    ])
  end
  
  defp deploy_production(version, plugins) do
    Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :s3,
      bucket: System.get_env("PROD_BUCKET") || "prod-tailwind-assets"
    ])
  end
end
```

## Telemetry & Monitoring

### Basic Telemetry Setup

```elixir
defmodule MyApp.TailwindWithTelemetry do
  def monitored_build(version, plugins) do
    # Start telemetry
    {:ok, _} = Defdo.TailwindBuilder.Telemetry.start_link([])
    
    # Perform build with automatic telemetry
    result = Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :local,
      output_dir: "./monitored-build"
    ])
    
    # Show telemetry stats
    stats = Defdo.TailwindBuilder.Telemetry.get_stats()
    IO.puts("Telemetry: #{stats.active_spans} active spans")
    
    result
  end
end
```

### Custom Metrics Recording

```elixir
defmodule MyApp.CustomMetrics do
  alias Defdo.TailwindBuilder.{Telemetry, Metrics}
  
  def build_with_metrics(version, plugins) do
    start_time = System.monotonic_time()
    
    # Start telemetry
    {:ok, _} = Telemetry.start_link([])
    
    # Record business metrics
    Metrics.record_business_metrics(:download, version, "MyApp/1.0")
    
    # Perform build
    result = Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :local,
      output_dir: "./dist"
    ])
    
    # Record completion metrics
    end_time = System.monotonic_time()
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    case result do
      {:ok, build_info} ->
        output_size = get_output_size(build_info)
        Metrics.record_build_metrics(version, plugins, duration_ms, output_size, :success)
        
      {:error, _} ->
        Metrics.record_build_metrics(version, plugins, duration_ms, 0, :error)
    end
    
    result
  end
  
  defp get_output_size(%{files: files}) do
    Enum.reduce(files, 0, fn file, acc ->
      case File.stat(file) do
        {:ok, %{size: size}} -> acc + size
        _ -> acc
      end
    end)
  end
  defp get_output_size(_), do: 0
end
```

### Live Dashboard

```elixir
defmodule MyApp.LiveMonitoring do
  alias Defdo.TailwindBuilder.Dashboard
  
  def start_monitoring do
    # Start telemetry
    {:ok, _} = Defdo.TailwindBuilder.Telemetry.start_link([])
    
    # Start live dashboard in a separate process
    spawn(fn ->
      Dashboard.display_live_dashboard(5) # 5 second refresh
    end)
    
    IO.puts("Live dashboard started! Ctrl+C to stop.")
  end
  
  def export_dashboard(format \\ :json) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    filename = "/tmp/tailwind_dashboard_#{timestamp}.#{format}"
    
    case Dashboard.export_dashboard(filename, format) do
      :ok -> 
        IO.puts("Dashboard exported to #{filename}")
        {:ok, filename}
      {:error, reason} -> 
        IO.puts("Export failed: #{reason}")
        {:error, reason}
    end
  end
end

# Usage
MyApp.LiveMonitoring.start_monitoring()
{:ok, file} = MyApp.LiveMonitoring.export_dashboard(:html)
```

## Custom Configuration

### Custom Config Provider

```elixir
defmodule MyApp.CustomConfigProvider do
  @behaviour Defdo.TailwindBuilder.ConfigProvider
  
  @impl true
  def get_supported_plugins do
    # Load from application config
    Application.get_env(:my_app, :tailwind_plugins, %{
      "daisyui" => %{
        "version" => ~s["daisyui": "^4.12.23"],
        "statement" => ~s['daisyui': require('daisyui')],
        "description" => "Company-approved DaisyUI version"
      }
    })
  end
  
  @impl true
  def get_operation_limits do
    # Custom timeouts based on environment
    base_timeout = if Mix.env() == :prod, do: 300_000, else: 60_000
    
    %{
      download_timeout: base_timeout,
      build_timeout: base_timeout * 2,
      max_file_size: 500_000_000, # 500MB
      max_concurrent_downloads: 2,
      retry_attempts: 3,
      cache_ttl: 1800 # 30 minutes
    }
  end
  
  @impl true
  def get_build_policies do
    %{
      allow_experimental_features: Mix.env() != :prod,
      skip_non_critical_validations: Mix.env() == :dev,
      enable_debug_symbols: Mix.env() == :dev,
      verbose_logging: Mix.env() in [:dev, :test],
      parallel_builds: true,
      incremental_builds: true
    }
  end
  
  @impl true
  def get_deployment_policies do
    %{
      skip_production_checks: Mix.env() != :prod,
      allow_overwrite: Mix.env() != :prod,
      backup_existing: Mix.env() == :prod,
      notify_on_deploy: Mix.env() == :prod,
      auto_cleanup_old: true,
      max_versions_kept: if(Mix.env() == :prod, do: 10, else: 3)
    }
  end
  
  @impl true
  def get_telemetry_config do
    %{
      enabled: true,
      level: if(Mix.env() == :prod, do: :info, else: :debug),
      backends: [:console],
      sample_rate: if(Mix.env() == :prod, do: 0.1, else: 1.0),
      trace_retention_hours: 24,
      detailed_logging: Mix.env() != :prod,
      performance_monitoring: true,
      error_tracking: :local
    }
  end
  
  # Optional callbacks with default implementations
  @impl true
  def get_known_checksums, do: %{}
  
  @impl true
  def get_version_policy(_version), do: :allowed
  
  @impl true
  def get_deployment_config(:local), do: %{destination: "./custom-dist"}
  def get_deployment_config(_), do: %{}
  
  @impl true
  def validate_operation_policy(_operation, _context), do: :ok
end

# Usage
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui"],
  target: :local,
  config_provider: MyApp.CustomConfigProvider
])
```

## Error Handling

### Comprehensive Error Handling

```elixir
defmodule MyApp.RobustBuilder do
  require Logger
  
  def build_with_fallback(version, plugins, targets) do
    case attempt_build(version, plugins, targets) do
      {:ok, results} -> 
        {:ok, results}
      {:error, reasons} -> 
        handle_build_failure(version, plugins, reasons)
    end
  end
  
  defp attempt_build(version, plugins, targets) do
    results = Enum.map(targets, fn target ->
      try do
        opts = build_opts(version, plugins, target)
        Defdo.TailwindBuilder.build_and_deploy(opts)
      rescue
        error -> 
          Logger.error("Build failed for #{target}: #{inspect(error)}")
          {:error, {target, error}}
      end
    end)
    
    case Enum.split_with(results, fn {status, _} -> status == :ok end) do
      {successes, []} -> 
        {:ok, successes}
      {successes, failures} -> 
        Logger.warning("#{length(successes)} succeeded, #{length(failures)} failed")
        {:error, failures}
    end
  end
  
  defp handle_build_failure(version, plugins, failures) do
    # Try with fallback configuration
    Logger.info("Attempting fallback build...")
    
    fallback_opts = [
      version: version,
      plugins: plugins,
      target: :local,
      output_dir: "/tmp/fallback-tailwind",
      config_provider: Defdo.TailwindBuilder.ConfigProviders.TestingConfigProvider
    ]
    
    case Defdo.TailwindBuilder.build_and_deploy(fallback_opts) do
      {:ok, result} -> 
        Logger.info("Fallback build succeeded")
        {:ok, %{fallback: result, original_failures: failures}}
      {:error, fallback_error} -> 
        Logger.error("Fallback build also failed: #{inspect(fallback_error)}")
        {:error, %{original: failures, fallback: fallback_error}}
    end
  end
  
  defp build_opts(version, plugins, :local) do
    [version: version, plugins: plugins, target: :local, output_dir: "./dist"]
  end
  
  defp build_opts(version, plugins, {:s3, bucket}) do
    [version: version, plugins: plugins, target: :s3, bucket: bucket]
  end
  
  defp build_opts(version, plugins, target) do
    [version: version, plugins: plugins, target: target]
  end
end

# Usage
targets = [:local, {:s3, "staging-bucket"}, {:s3, "prod-bucket"}]
case MyApp.RobustBuilder.build_with_fallback("4.1.11", ["daisyui"], targets) do
  {:ok, results} -> 
    IO.puts("All builds succeeded!")
  {:error, details} -> 
    IO.puts("Some builds failed: #{inspect(details)}")
end
```

### Retry Logic

```elixir
defmodule MyApp.RetryBuilder do
  def build_with_retry(version, plugins, max_attempts \\ 3) do
    attempt_with_backoff(version, plugins, max_attempts, 1)
  end
  
  defp attempt_with_backoff(version, plugins, 0, attempt) do
    Logger.error("All #{attempt - 1} attempts failed")
    {:error, :max_attempts_exceeded}
  end
  
  defp attempt_with_backoff(version, plugins, remaining, attempt) do
    Logger.info("Build attempt #{attempt}")
    
    case Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :local,
      output_dir: "./dist"
    ]) do
      {:ok, result} -> 
        Logger.info("Build succeeded on attempt #{attempt}")
        {:ok, result}
        
      {:error, reason} -> 
        Logger.warning("Attempt #{attempt} failed: #{inspect(reason)}")
        
        if remaining > 1 do
          backoff_ms = :math.pow(2, attempt) * 1000 |> round()
          Logger.info("Retrying in #{backoff_ms}ms...")
          Process.sleep(backoff_ms)
        end
        
        attempt_with_backoff(version, plugins, remaining - 1, attempt + 1)
    end
  end
end
```

## Integration Examples

### Phoenix Application Integration

```elixir
defmodule MyAppWeb.TailwindController do
  use MyAppWeb, :controller
  
  def build(conn, %{"version" => version, "plugins" => plugins}) do
    case build_tailwind(version, plugins) do
      {:ok, result} -> 
        json(conn, %{status: "success", result: result})
      {:error, reason} -> 
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", reason: inspect(reason)})
    end
  end
  
  def status(conn, _params) do
    stats = get_telemetry_stats()
    json(conn, stats)
  end
  
  defp build_tailwind(version, plugins) do
    # Start telemetry if not already running
    ensure_telemetry_started()
    
    Defdo.TailwindBuilder.build_and_deploy([
      version: version,
      plugins: plugins,
      target: :local,
      output_dir: Path.join([:code.priv_dir(:my_app), "static", "css"])
    ])
  end
  
  defp ensure_telemetry_started do
    case Process.whereis(Defdo.TailwindBuilder.Telemetry) do
      nil -> Defdo.TailwindBuilder.Telemetry.start_link([])
      _pid -> {:ok, :already_started}
    end
  end
  
  defp get_telemetry_stats do
    if Process.whereis(Defdo.TailwindBuilder.Telemetry) do
      Defdo.TailwindBuilder.Telemetry.get_stats()
    else
      %{enabled: false}
    end
  end
end
```

### GenServer Integration

```elixir
defmodule MyApp.TailwindService do
  use GenServer
  require Logger
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def build_async(version, plugins, target \\ :local) do
    GenServer.cast(__MODULE__, {:build, version, plugins, target})
  end
  
  def get_status do
    GenServer.call(__MODULE__, :status)
  end
  
  def get_history do
    GenServer.call(__MODULE__, :history)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Start telemetry
    {:ok, _} = Defdo.TailwindBuilder.Telemetry.start_link([])
    
    state = %{
      active_builds: %{},
      build_history: [],
      max_history: 50
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:build, version, plugins, target}, state) do
    build_id = generate_build_id()
    
    # Start build in separate process
    pid = spawn_link(fn ->
      result = perform_build(build_id, version, plugins, target)
      GenServer.cast(__MODULE__, {:build_complete, build_id, result})
    end)
    
    # Track active build
    active_builds = Map.put(state.active_builds, build_id, %{
      pid: pid,
      version: version,
      plugins: plugins,
      target: target,
      started_at: DateTime.utc_now()
    })
    
    Logger.info("Started build #{build_id} for version #{version}")
    
    {:noreply, %{state | active_builds: active_builds}}
  end
  
  @impl true
  def handle_cast({:build_complete, build_id, result}, state) do
    case Map.pop(state.active_builds, build_id) do
      {nil, _} -> 
        {:noreply, state}
        
      {build_info, remaining_builds} ->
        # Add to history
        history_entry = Map.merge(build_info, %{
          id: build_id,
          completed_at: DateTime.utc_now(),
          result: result
        })
        
        new_history = [history_entry | state.build_history]
        |> Enum.take(state.max_history)
        
        Logger.info("Build #{build_id} completed: #{inspect(result)}")
        
        {:noreply, %{state | 
          active_builds: remaining_builds,
          build_history: new_history
        }}
    end
  end
  
  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      active_builds: map_size(state.active_builds),
      total_builds: length(state.build_history),
      telemetry_stats: Defdo.TailwindBuilder.Telemetry.get_stats()
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call(:history, _from, state) do
    {:reply, state.build_history, state}
  end
  
  # Private Functions
  
  defp generate_build_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp perform_build(build_id, version, plugins, target) do
    Logger.info("Executing build #{build_id}")
    
    opts = [
      version: version,
      plugins: plugins,
      target: target,
      output_dir: "./builds/#{build_id}"
    ]
    
    Defdo.TailwindBuilder.build_and_deploy(opts)
  end
end

# Usage
{:ok, _pid} = MyApp.TailwindService.start_link()

# Async builds
MyApp.TailwindService.build_async("4.1.11", ["daisyui"])
MyApp.TailwindService.build_async("3.4.17", ["@tailwindcss/typography"])

# Check status
status = MyApp.TailwindService.get_status()
IO.inspect(status)

# View history
history = MyApp.TailwindService.get_history()
IO.inspect(history)
```

### Mix Task Integration

```elixir
defmodule Mix.Tasks.Tailwind.Build do
  use Mix.Task
  
  @shortdoc "Build TailwindCSS with plugins"
  @moduledoc """
  Build TailwindCSS with specified plugins.
  
  ## Usage
  
      mix tailwind.build --version 4.1.11 --plugins daisyui,@tailwindcss/typography --target local --output ./assets/css
  
  ## Options
  
    * `--version` - TailwindCSS version to build (required)
    * `--plugins` - Comma-separated list of plugins  
    * `--target` - Deployment target (local, s3, r2, cdn)
    * `--output` - Output directory for local builds
    * `--bucket` - S3/R2 bucket name for cloud deployment
    * `--telemetry` - Enable telemetry (true/false, default: true)
    * `--verbose` - Enable verbose output
  
  ## Examples
  
      mix tailwind.build --version 4.1.11 --plugins daisyui --target local --output ./dist
      mix tailwind.build --version 4.1.11 --plugins daisyui,@tailwindcss/typography --target s3 --bucket my-assets
  """
  
  def run(args) do
    # Start application
    Application.ensure_all_started(:tailwind_builder)
    
    {opts, _} = OptionParser.parse!(args, 
      strict: [
        version: :string,
        plugins: :string,
        target: :string,
        output: :string,
        bucket: :string,
        telemetry: :boolean,
        verbose: :boolean
      ],
      aliases: [
        v: :version,
        p: :plugins,
        t: :target,
        o: :output,
        b: :bucket
      ]
    )
    
    # Validate required options
    version = opts[:version] || Mix.raise("--version is required")
    
    # Parse plugins
    plugins = case opts[:plugins] do
      nil -> []
      plugin_string -> String.split(plugin_string, ",") |> Enum.map(&String.trim/1)
    end
    
    # Configure telemetry
    if Keyword.get(opts, :telemetry, true) do
      {:ok, _} = Defdo.TailwindBuilder.Telemetry.start_link([])
      Mix.shell().info("Telemetry enabled")
    end
    
    # Configure verbosity
    if opts[:verbose] do
      Logger.configure(level: :debug)
    end
    
    # Build options
    build_opts = [
      version: version,
      plugins: plugins
    ]
    |> add_target_opts(opts)
    
    Mix.shell().info("Building TailwindCSS #{version} with plugins: #{inspect(plugins)}")
    
    # Perform build
    case Defdo.TailwindBuilder.build_and_deploy(build_opts) do
      {:ok, result} ->
        Mix.shell().info("✅ Build successful!")
        
        if opts[:verbose] do
          Mix.shell().info("Result: #{inspect(result, pretty: true)}")
        end
        
        # Show telemetry summary if enabled
        if opts[:telemetry] do
          show_telemetry_summary()
        end
        
      {:error, reason} ->
        Mix.shell().error("❌ Build failed: #{inspect(reason)}")
        System.halt(1)
    end
  end
  
  defp add_target_opts(opts, %{target: "local", output: output}) when is_binary(output) do
    [{:target, :local}, {:output_dir, output} | opts]
  end
  
  defp add_target_opts(opts, %{target: "s3", bucket: bucket}) when is_binary(bucket) do
    [{:target, :s3}, {:bucket, bucket} | opts]
  end
  
  defp add_target_opts(opts, %{target: "r2", bucket: bucket}) when is_binary(bucket) do
    [{:target, :r2}, {:bucket, bucket} | opts]
  end
  
  defp add_target_opts(opts, %{target: target}) when is_binary(target) do
    [{:target, String.to_atom(target)} | opts]
  end
  
  defp add_target_opts(opts, _) do
    # Default to local
    [{:target, :local}, {:output_dir, "./dist"} | opts]
  end
  
  defp show_telemetry_summary do
    stats = Defdo.TailwindBuilder.Telemetry.get_stats()
    Mix.shell().info("\n📊 Telemetry Summary:")
    Mix.shell().info("   Active spans: #{stats.active_spans}")
    Mix.shell().info("   Total metrics: #{stats.total_metrics}")
  end
end
```

---

These examples demonstrate the flexibility and power of TailwindBuilder's modular architecture. Each example can be adapted to your specific use case and requirements.