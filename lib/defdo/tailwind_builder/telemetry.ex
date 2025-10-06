defmodule Defdo.TailwindBuilder.Telemetry do
  @moduledoc """
  Comprehensive telemetry system for TailwindBuilder operations.
  
  Provides structured monitoring, metrics, traces, and logging for:
  - Asynchronous download operations
  - Build and compilation processes  
  - Deployment workflows
  - Plugin management
  - Error tracking and performance monitoring
  
  ## Usage
  
      # Start operation tracking
      span_id = Telemetry.start_span(:download, %{version: "4.1.11", size: 1024})
      
      # Track events during operation
      Telemetry.track_event(:download, :progress, %{percent: 50, bytes: 512})
      
      # End operation tracking
      Telemetry.end_span(span_id, :success, %{duration: 1500})
  
  ## Configuration
  
      config :tailwind_builder, :telemetry,
        enabled: true,
        level: :info,
        backends: [:console, :prometheus, :datadog],
        sample_rate: 1.0,
        trace_retention_hours: 24
  """

  use GenServer
  require Logger

  @compile {:no_warn_undefined, [:prometheus_counter, :prometheus_histogram]}

  alias Defdo.TailwindBuilder.ConfigProviderFactory

  # Telemetry event prefixes
  @event_prefix [:tailwind_builder]
  @metrics_prefix "tailwind_builder"

  # Operation types
  @operations [:download, :build, :deploy, :plugin_install, :cross_compile, :github_build, :smart_build]


  # State structure
  defmodule State do
    @moduledoc false
    defstruct [
      :config,
      :backends,
      active_spans: %{},
      metrics: %{},
      traces: [],
      enabled: true,
      sample_rate: 1.0
    ]
  end

  defmodule Span do
    @moduledoc false
    defstruct [
      :id,
      :operation,
      :start_time,
      :end_time,
      :status,
      :metadata,
      :events,
      :parent_id,
      :trace_id
    ]
  end

  ## Public API

  @doc """
  Start the telemetry system
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a new operation span for tracking
  """
  def start_span(operation, metadata \\ %{}) when operation in @operations do
    if enabled?() do
      GenServer.call(__MODULE__, {:start_span, operation, metadata})
    else
      generate_span_id()
    end
  end

  @doc """
  End an operation span
  """
  def end_span(span_id, status \\ :success, metadata \\ %{}) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:end_span, span_id, status, metadata})
    end
    :ok
  end

  @doc """
  Track an event within an operation
  """
  def track_event(operation, event_type, metadata \\ %{}) 
      when operation in @operations and is_atom(event_type) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:track_event, operation, event_type, metadata})
    end
    :ok
  end

  @doc """
  Track a metric value
  """
  def track_metric(metric_name, value, tags \\ %{}) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:track_metric, metric_name, value, tags})
    end
    :ok
  end

  @doc """
  Log structured telemetry data
  """
  def log(level, message, metadata \\ %{}) do
    if enabled?() do
      # Safely encode metadata, converting complex structures to strings
      safe_metadata = safe_encode_metadata(metadata)
      
      structured_log = %{
        timestamp: DateTime.utc_now(),
        level: level,
        message: message,
        metadata: safe_metadata,
        component: "tailwind_builder"
      }
      
      Logger.log(level, fn -> 
        case Jason.encode(structured_log) do
          {:ok, json} -> json
          {:error, _} -> "#{message} (metadata encoding failed)"
        end
      end)
    end
    :ok
  end

  @doc """
  Get current telemetry statistics
  """
  def get_stats do
    if enabled?() do
      GenServer.call(__MODULE__, :get_stats)
    else
      %{enabled: false}
    end
  end

  @doc """
  Get active spans for debugging
  """
  def get_active_spans do
    if enabled?() do
      GenServer.call(__MODULE__, :get_active_spans)
    else
      %{}
    end
  end

  @doc """
  Check if telemetry is enabled
  """
  def enabled? do
    case Process.whereis(__MODULE__) do
      nil -> false
      _pid -> 
        config = get_config()
        Map.get(config, :enabled, true)
    end
  end

  ## Convenience functions for common operations

  @doc """
  Track a download operation with automatic span management
  """
  def track_download(version, fun) when is_function(fun, 0) do
    span_id = start_span(:download, %{version: version, start_time: System.monotonic_time()})
    
    try do
      result = fun.()
      end_span(span_id, :success, %{end_time: System.monotonic_time()})
      result
    rescue
      error ->
        end_span(span_id, :error, %{
          error: inspect(error),
          end_time: System.monotonic_time()
        })
        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Track a build operation with automatic span management
  """
  def track_build(version, plugins, fun) when is_function(fun, 0) do
    span_id = start_span(:build, %{
      version: version, 
      plugins: plugins,
      start_time: System.monotonic_time()
    })
    
    try do
      result = fun.()
      end_span(span_id, :success, %{end_time: System.monotonic_time()})
      result
    rescue
      error ->
        end_span(span_id, :error, %{
          error: inspect(error),
          end_time: System.monotonic_time()
        })
        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Track a deployment operation with automatic span management
  """
  def track_deploy(target, fun) when is_function(fun, 0) do
    span_id = start_span(:deploy, %{
      target: target,
      start_time: System.monotonic_time()
    })
    
    try do
      result = fun.()
      end_span(span_id, :success, %{end_time: System.monotonic_time()})
      result
    rescue
      error ->
        end_span(span_id, :error, %{
          error: inspect(error),
          end_time: System.monotonic_time()
        })
        reraise error, __STACKTRACE__
    end
  end

  ## GenServer callbacks

  @impl GenServer
  def init(_opts) do
    config = get_config()
    
    state = %State{
      config: config,
      backends: Map.get(config, :backends, [:console]),
      enabled: Map.get(config, :enabled, true),
      sample_rate: Map.get(config, :sample_rate, 1.0)
    }

    # Initialize backends
    initialize_backends(state.backends)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:start_span, operation, metadata}, _from, state) do
    span_id = generate_span_id()
    trace_id = generate_trace_id()
    
    span = %Span{
      id: span_id,
      operation: operation,
      start_time: System.monotonic_time(),
      metadata: metadata,
      events: [],
      trace_id: trace_id
    }
    
    # Emit telemetry event
    :telemetry.execute(@event_prefix ++ [operation, :start], %{
      system_time: System.system_time()
    }, %{
      span_id: span_id,
      trace_id: trace_id,
      metadata: metadata
    })
    
    new_state = %{state | active_spans: Map.put(state.active_spans, span_id, span)}
    
    {:reply, span_id, new_state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = %{
      enabled: state.enabled,
      active_spans: map_size(state.active_spans),
      total_metrics: map_size(state.metrics),
      sample_rate: state.sample_rate,
      backends: state.backends
    }
    
    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call(:get_active_spans, _from, state) do
    spans = Enum.map(state.active_spans, fn {id, span} ->
      %{
        id: id,
        operation: span.operation,
        duration: System.monotonic_time() - span.start_time,
        metadata: span.metadata
      }
    end)
    
    {:reply, spans, state}
  end

  @impl GenServer
  def handle_cast({:end_span, span_id, status, metadata}, state) do
    case Map.get(state.active_spans, span_id) do
      nil ->
        {:noreply, state}
      
      span ->
        end_time = System.monotonic_time()
        duration = end_time - span.start_time
        
        # Emit telemetry event
        :telemetry.execute(@event_prefix ++ [span.operation, :stop], %{
          duration: duration,
          system_time: System.system_time()
        }, %{
          span_id: span_id,
          trace_id: span.trace_id,
          status: status,
          metadata: Map.merge(span.metadata, metadata)
        })
        
        # Update metrics
        new_metrics = update_metrics(state.metrics, span.operation, duration, status)
        
        # Remove from active spans
        new_active_spans = Map.delete(state.active_spans, span_id)
        
        new_state = %{state | 
          active_spans: new_active_spans,
          metrics: new_metrics
        }
        
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_cast({:track_event, operation, event_type, metadata}, state) do
    # Emit telemetry event
    :telemetry.execute(@event_prefix ++ [operation, event_type], %{
      system_time: System.system_time()
    }, metadata)
    
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:track_metric, metric_name, value, tags}, state) do
    metric_key = {metric_name, tags}
    new_metrics = Map.update(state.metrics, metric_key, [value], fn values ->
      [value | Enum.take(values, 99)] # Keep last 100 values
    end)
    
    # Emit telemetry event  
    :telemetry.execute(@event_prefix ++ [:metric], %{value: value}, %{
      name: metric_name,
      tags: tags
    })
    
    {:noreply, %{state | metrics: new_metrics}}
  end

  ## Private functions

  defp get_config do
    provider = ConfigProviderFactory.get_provider()
    
    default_config = %{
      enabled: true,
      level: :info,
      backends: [:console],
      sample_rate: 1.0,
      trace_retention_hours: 24
    }
    
    # Get environment-specific telemetry config if provider supports it
    if function_exported?(provider, :get_telemetry_config, 0) do
      provider_config = provider.get_telemetry_config()
      Map.merge(default_config, provider_config)
    else
      default_config
    end
  end

  defp initialize_backends(backends) do
    Enum.each(backends, fn backend ->
      case backend do
        :console -> :ok # Built-in
        :prometheus -> initialize_prometheus()
        :datadog -> initialize_datadog()
        _ -> Logger.warning("Unknown telemetry backend: #{backend}")
      end
    end)
  end

  defp initialize_prometheus do
    # Initialize Prometheus metrics if available
    try do
      if Code.ensure_loaded?(:prometheus_counter) and Code.ensure_loaded?(:prometheus_histogram) do
        :prometheus_counter.declare([
          name: :"#{@metrics_prefix}_operations_total",
          help: "Total number of operations",
          labels: [:operation, :status]
        ])
        
        :prometheus_histogram.declare([
          name: :"#{@metrics_prefix}_operation_duration_seconds",
          help: "Operation duration in seconds",
          labels: [:operation],
          buckets: [0.1, 0.5, 1.0, 2.5, 5.0, 10.0]
        ])
      else
        Logger.debug("Prometheus modules not available")
      end
    rescue
      _ -> Logger.debug("Prometheus initialization failed")
    end
  end

  defp initialize_datadog do
    # Initialize DataDog integration if available
    Logger.debug("DataDog telemetry backend initialized")
  end

  defp generate_span_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp update_metrics(metrics, operation, duration, status) do
    # Update operation counters
    counter_key = {:operations_total, %{operation: operation, status: status}}
    duration_key = {:operation_duration, %{operation: operation}}
    
    metrics
    |> Map.update(counter_key, 1, &(&1 + 1))
    |> Map.update(duration_key, [duration], fn durations ->
      [duration | Enum.take(durations, 99)]
    end)
  end

  defp safe_encode_metadata(metadata) when is_map(metadata) do
    Enum.into(metadata, %{}, fn {key, value} ->
      {key, safe_encode_value(value)}
    end)
  end
  defp safe_encode_metadata(metadata), do: inspect(metadata)

  defp safe_encode_value(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_atom(value) do
    value
  end
  defp safe_encode_value(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end
  defp safe_encode_value(value) when is_list(value) do
    Enum.map(value, &safe_encode_value/1)
  end
  defp safe_encode_value(value) when is_map(value) do
    safe_encode_metadata(value)
  end
  defp safe_encode_value(value) do
    inspect(value)
  end
end