defmodule Defdo.TailwindBuilder.Metrics do
  @moduledoc """
  Specialized metrics collection and reporting for TailwindBuilder.
  
  Provides:
  - Performance metrics for async operations
  - Resource utilization tracking  
  - Error rate monitoring
  - Business metrics (downloads, builds, deployments)
  - SLA and performance indicators
  """

  @compile {:no_warn_undefined, [:cpu_sup]}

  alias Defdo.TailwindBuilder.Telemetry

  @doc """
  Record download metrics
  """
  def record_download_metrics(version, size_bytes, duration_ms, status) do
    base_tags = %{
      version_major: extract_major_version(version),
      status: status
    }
    
    # Core download metrics
    Telemetry.track_metric("download.count", 1, base_tags)
    Telemetry.track_metric("download.size_bytes", size_bytes, base_tags)
    Telemetry.track_metric("download.duration_ms", duration_ms, base_tags)
    
    # Derived metrics
    if duration_ms > 0 do
      throughput_mbps = (size_bytes * 8) / (duration_ms * 1000) # Mbps
      Telemetry.track_metric("download.throughput_mbps", throughput_mbps, base_tags)
    end
    
    # Error tracking
    if status == :error do
      Telemetry.track_metric("download.errors", 1, base_tags)
    end
    
    :ok
  end

  @doc """
  Record build metrics
  """
  def record_build_metrics(version, plugins, duration_ms, output_size, status) do
    base_tags = %{
      version_major: extract_major_version(version),
      plugin_count: length(plugins),
      status: status
    }
    
    # Core build metrics
    Telemetry.track_metric("build.count", 1, base_tags)
    Telemetry.track_metric("build.duration_ms", duration_ms, base_tags)
    Telemetry.track_metric("build.output_size_bytes", output_size, base_tags)
    
    # Plugin-specific metrics
    Enum.each(plugins, fn plugin ->
      Telemetry.track_metric("build.plugin_usage", 1, %{plugin: plugin})
    end)
    
    # Performance indicators
    if duration_ms > 0 and output_size > 0 do
      build_rate = output_size / duration_ms # bytes per ms
      Telemetry.track_metric("build.rate_bytes_per_ms", build_rate, base_tags)
    end
    
    :ok
  end

  @doc """
  Record deployment metrics
  """
  def record_deployment_metrics(target, file_count, total_size, duration_ms, status) do
    base_tags = %{
      target: target,
      status: status
    }
    
    # Core deployment metrics
    Telemetry.track_metric("deploy.count", 1, base_tags)
    Telemetry.track_metric("deploy.duration_ms", duration_ms, base_tags)
    Telemetry.track_metric("deploy.file_count", file_count, base_tags)
    Telemetry.track_metric("deploy.total_size_bytes", total_size, base_tags)
    
    # Upload performance
    if duration_ms > 0 and total_size > 0 do
      upload_rate = total_size / duration_ms # bytes per ms
      Telemetry.track_metric("deploy.upload_rate_bytes_per_ms", upload_rate, base_tags)
    end
    
    :ok
  end

  @doc """
  Record system resource metrics
  """
  def record_resource_metrics do
    # Memory usage
    {:memory, memory_info} = :erlang.memory() |> List.keyfind(:memory, 0, {:memory, []})
    
    memory_data = Enum.into(memory_info, %{})
    
    Telemetry.track_metric("system.memory.total", Map.get(memory_data, :total, 0))
    Telemetry.track_metric("system.memory.processes", Map.get(memory_data, :processes, 0))
    Telemetry.track_metric("system.memory.ets", Map.get(memory_data, :ets, 0))
    Telemetry.track_metric("system.memory.binary", Map.get(memory_data, :binary, 0))
    
    # Process count
    process_count = :erlang.system_info(:process_count)
    Telemetry.track_metric("system.processes.count", process_count)
    
    # Load average (if available)
    try do
      if Code.ensure_loaded?(:cpu_sup) do
        case :cpu_sup.avg1() do
          {:ok, load} -> Telemetry.track_metric("system.load.avg1", load)
          _ -> :ok
        end
      else
        :ok
      end
    rescue
      UndefinedFunctionError -> :ok  # cpu_sup not available
    end
    
    :ok
  end

  @doc """
  Record error metrics with categorization
  """
  def record_error_metrics(operation, error_type, error_details) do
    base_tags = %{
      operation: operation,
      error_type: error_type
    }
    
    Telemetry.track_metric("errors.count", 1, base_tags)
    
    # Log structured error for analysis
    Telemetry.log(:error, "Operation failed", %{
      operation: operation,
      error_type: error_type,
      error_details: error_details,
      timestamp: DateTime.utc_now()
    })
    
    :ok
  end

  @doc """
  Record cache hit/miss metrics
  """
  def record_cache_metrics(operation, _cache_key, hit_or_miss) do
    base_tags = %{
      operation: operation,
      result: hit_or_miss
    }
    
    Telemetry.track_metric("cache.requests", 1, base_tags)
    
    if hit_or_miss == :hit do
      Telemetry.track_metric("cache.hits", 1, %{operation: operation})
    else
      Telemetry.track_metric("cache.misses", 1, %{operation: operation})
    end
    
    :ok
  end

  @doc """
  Calculate and record SLA metrics
  """
  def record_sla_metrics(operation, start_time, end_time, success?) do
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    base_tags = %{operation: operation}
    
    # Availability metrics
    if success? do
      Telemetry.track_metric("sla.success", 1, base_tags)
    else
      Telemetry.track_metric("sla.failure", 1, base_tags)
    end
    
    # Latency SLA tracking
    sla_thresholds = get_sla_thresholds(operation)
    
    Enum.each(sla_thresholds, fn {threshold_name, threshold_ms} ->
      if duration_ms <= threshold_ms do
        Telemetry.track_metric("sla.#{threshold_name}_met", 1, base_tags)
      else
        Telemetry.track_metric("sla.#{threshold_name}_missed", 1, base_tags)
      end
    end)
    
    :ok
  end

  @doc """
  Generate business intelligence metrics
  """
  def record_business_metrics(operation, version, user_agent \\ nil) do
    base_tags = %{
      operation: operation,
      version_major: extract_major_version(version)
    }
    
    # Usage patterns
    Telemetry.track_metric("usage.operations", 1, base_tags)
    
    # Version adoption
    Telemetry.track_metric("versions.usage", 1, %{version: version})
    
    # User agent tracking (if provided)
    if user_agent do
      parsed_agent = parse_user_agent(user_agent)
      Telemetry.track_metric("usage.client", 1, parsed_agent)
    end
    
    # Time-based patterns
    hour = DateTime.utc_now().hour
    day_of_week = Date.day_of_week(Date.utc_today())
    
    Telemetry.track_metric("usage.by_hour", 1, %{hour: hour})
    Telemetry.track_metric("usage.by_day", 1, %{day_of_week: day_of_week})
    
    :ok
  end

  @doc """
  Get metrics summary for monitoring dashboards
  """
  def get_metrics_summary(time_window_minutes \\ 60) do
    stats = Telemetry.get_stats()
    
    %{
      system: %{
        enabled: Map.get(stats, :enabled, false),
        active_spans: Map.get(stats, :active_spans, 0),
        uptime: get_uptime_seconds()
      },
      operations: get_operation_summary(time_window_minutes),
      errors: get_error_summary(time_window_minutes),
      performance: get_performance_summary(time_window_minutes)
    }
  end

  ## Private functions

  defp extract_major_version(version) do
    case String.split(version, ".") do
      [major | _] -> major
      _ -> "unknown"
    end
  end

  defp get_sla_thresholds(operation) do
    case operation do
      :download -> [
        {:p95, 30_000},    # 30 seconds
        {:p99, 60_000}     # 60 seconds
      ]
      :build -> [
        {:p95, 120_000},   # 2 minutes
        {:p99, 300_000}    # 5 minutes
      ]
      :deploy -> [
        {:p95, 60_000},    # 1 minute
        {:p99, 180_000}    # 3 minutes
      ]
      _ -> [
        {:p95, 10_000},    # 10 seconds
        {:p99, 30_000}     # 30 seconds
      ]
    end
  end

  defp parse_user_agent(user_agent) do
    # Simple user agent parsing
    cond do
      String.contains?(user_agent, "curl") -> %{client: "curl"}
      String.contains?(user_agent, "wget") -> %{client: "wget"}
      String.contains?(user_agent, "elixir") -> %{client: "elixir"}
      String.contains?(user_agent, "phoenix") -> %{client: "phoenix"}
      true -> %{client: "unknown"}
    end
  end

  defp get_uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end

  defp get_operation_summary(_time_window) do
    # This would query actual metrics storage in a real implementation
    %{
      downloads: %{total: 0, success: 0, errors: 0},
      builds: %{total: 0, success: 0, errors: 0},
      deployments: %{total: 0, success: 0, errors: 0}
    }
  end

  defp get_error_summary(_time_window) do
    %{
      total_errors: 0,
      error_rate: 0.0,
      top_errors: []
    }
  end

  defp get_performance_summary(_time_window) do
    %{
      avg_download_time: 0,
      avg_build_time: 0,
      avg_deploy_time: 0,
      p95_latency: 0,
      p99_latency: 0
    }
  end
end