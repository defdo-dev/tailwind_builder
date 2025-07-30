defmodule Defdo.TailwindBuilder.Dashboard do
  @moduledoc """
  Simple dashboard for monitoring TailwindBuilder telemetry in real-time.
  
  Provides:
  - Real-time metrics visualization
  - Operation status monitoring  
  - Error rate tracking
  - Performance indicators
  - System health overview
  """

  alias Defdo.TailwindBuilder.Telemetry

  @doc """
  Generate a comprehensive dashboard summary
  """
  def generate_summary(opts \\ []) do
    time_window = Keyword.get(opts, :time_window_minutes, 60)
    format = Keyword.get(opts, :format, :text)
    
    summary = %{
      timestamp: DateTime.utc_now(),
      time_window_minutes: time_window,
      system_health: get_system_health(),
      operations: get_operations_summary(),
      performance: get_performance_summary(),
      errors: get_errors_summary(),
      active_spans: Telemetry.get_active_spans()
    }
    
    case format do
      :json -> Jason.encode!(summary, pretty: true)
      :text -> format_text_dashboard(summary)
      :html -> format_html_dashboard(summary)
      :raw -> summary
      _ -> summary
    end
  end

  @doc """
  Get real-time system health indicators
  """
  def get_system_health do
    telemetry_stats = Telemetry.get_stats()
    
    %{
      telemetry_enabled: Map.get(telemetry_stats, :enabled, false),
      active_operations: Map.get(telemetry_stats, :active_spans, 0),
      system_uptime_seconds: get_system_uptime(),
      memory_usage: get_memory_health(),
      process_count: :erlang.system_info(:process_count),
      load_average: get_load_average(),
      status: determine_system_status()
    }
  end

  @doc """
  Get operations summary with success/failure rates
  """
  def get_operations_summary do
    # In a real implementation, this would query metrics storage
    %{
      downloads: %{
        total: get_operation_count(:download),
        success_rate: get_success_rate(:download),
        avg_duration_ms: get_avg_duration(:download),
        last_24h: get_operation_count(:download, 24 * 60)
      },
      builds: %{
        total: get_operation_count(:build),
        success_rate: get_success_rate(:build),
        avg_duration_ms: get_avg_duration(:build),
        last_24h: get_operation_count(:build, 24 * 60)
      },
      deployments: %{
        total: get_operation_count(:deploy),
        success_rate: get_success_rate(:deploy),
        avg_duration_ms: get_avg_duration(:deploy),
        last_24h: get_operation_count(:deploy, 24 * 60)
      }
    }
  end

  @doc """
  Get performance metrics and SLA indicators
  """
  def get_performance_summary do
    %{
      response_times: %{
        p50: get_percentile(:duration, 50),
        p95: get_percentile(:duration, 95),
        p99: get_percentile(:duration, 99)
      },
      throughput: %{
        requests_per_minute: get_requests_per_minute(),
        avg_download_speed_mbps: get_avg_download_speed(),
        avg_build_rate_bytes_per_ms: get_avg_build_rate()
      },
      sla_compliance: %{
        download_sla_met: get_sla_compliance(:download),
        build_sla_met: get_sla_compliance(:build),
        deploy_sla_met: get_sla_compliance(:deploy)
      }
    }
  end

  @doc """
  Get error summary and patterns
  """
  def get_errors_summary do
    %{
      total_errors: get_total_errors(),
      error_rate_percent: get_error_rate(),
      top_errors: get_top_errors(5),
      errors_by_operation: %{
        download: get_error_count(:download),
        build: get_error_count(:build),
        deploy: get_error_count(:deploy)
      },
      recent_errors: get_recent_errors(10)
    }
  end

  @doc """
  Display real-time dashboard in terminal
  """
  def display_live_dashboard(refresh_seconds \\ 10) do
    clear_screen()
    
    Stream.interval(refresh_seconds * 1000)
    |> Enum.each(fn _ ->
      clear_screen()
      summary = generate_summary(format: :text)
      IO.puts(summary)
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("Refreshing every #{refresh_seconds} seconds... (Ctrl+C to exit)")
    end)
  end

  @doc """
  Export dashboard data to file
  """
  def export_dashboard(filename, format \\ :json) do
    summary = generate_summary(format: format)
    
    case File.write(filename, summary) do
      :ok -> 
        IO.puts("Dashboard exported to #{filename}")
        :ok
      {:error, reason} -> 
        IO.puts("Failed to export dashboard: #{reason}")
        {:error, reason}
    end
  end

  ## Private functions

  defp format_text_dashboard(summary) do
    """
    ╔════════════════════════════════════════════════════════════════════════════════╗
    ║                           TAILWIND BUILDER DASHBOARD                           ║
    ║                        #{summary.timestamp}                         ║
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ SYSTEM HEALTH                                                                  ║
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ Status: #{format_status(summary.system_health.status)}                                      
    ║ Telemetry: #{if summary.system_health.telemetry_enabled, do: "ENABLED", else: "DISABLED"}
    ║ Active Operations: #{summary.system_health.active_operations}
    ║ Uptime: #{format_uptime(summary.system_health.system_uptime_seconds)}
    ║ Memory Usage: #{format_memory(summary.system_health.memory_usage)}
    ║ Process Count: #{summary.system_health.process_count}
    ║ Load Average: #{format_load(summary.system_health.load_average)}
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ OPERATIONS SUMMARY (Last #{summary.time_window_minutes} minutes)                                      ║
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ Downloads:   #{format_operation_stats(summary.operations.downloads)}
    ║ Builds:      #{format_operation_stats(summary.operations.builds)}
    ║ Deployments: #{format_operation_stats(summary.operations.deployments)}
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ PERFORMANCE METRICS                                                            ║
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ Response Times: P50: #{summary.performance.response_times.p50}ms | P95: #{summary.performance.response_times.p95}ms | P99: #{summary.performance.response_times.p99}ms
    ║ Throughput: #{summary.performance.throughput.requests_per_minute} req/min
    ║ Download Speed: #{summary.performance.throughput.avg_download_speed_mbps} Mbps avg
    ║ SLA Compliance: Download: #{summary.performance.sla_compliance.download_sla_met}% | Build: #{summary.performance.sla_compliance.build_sla_met}% | Deploy: #{summary.performance.sla_compliance.deploy_sla_met}%
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ ERROR SUMMARY                                                                  ║
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ Total Errors: #{summary.errors.total_errors}
    ║ Error Rate: #{summary.errors.error_rate_percent}%
    ║ Top Errors: #{format_top_errors(summary.errors.top_errors)}
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║ ACTIVE OPERATIONS                                                              ║
    ╠════════════════════════════════════════════════════════════════════════════════╣
    #{format_active_spans(summary.active_spans)}
    ╚════════════════════════════════════════════════════════════════════════════════╝
    """
  end

  defp format_html_dashboard(summary) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>TailwindBuilder Dashboard</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: monospace; margin: 20px; background: #1a1a1a; color: #00ff00; }
            .container { max-width: 1200px; margin: 0 auto; }
            .section { margin: 20px 0; padding: 15px; border: 1px solid #333; border-radius: 5px; }
            .header { text-align: center; font-size: 1.5em; margin-bottom: 20px; }
            .status-ok { color: #00ff00; }
            .status-warn { color: #ffff00; }
            .status-error { color: #ff0000; }
            .metric { display: inline-block; margin: 10px; padding: 10px; border: 1px solid #555; }
            table { width: 100%; border-collapse: collapse; }
            th, td { padding: 8px; text-align: left; border-bottom: 1px solid #333; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">TailwindBuilder Dashboard - #{summary.timestamp}</div>
            
            <div class="section">
                <h3>System Health</h3>
                <div class="metric">Status: <span class="status-#{String.downcase(to_string(summary.system_health.status))}">#{summary.system_health.status}</span></div>
                <div class="metric">Active Operations: #{summary.system_health.active_operations}</div>
                <div class="metric">Uptime: #{format_uptime(summary.system_health.system_uptime_seconds)}</div>
                <div class="metric">Memory: #{format_memory(summary.system_health.memory_usage)}</div>
            </div>
            
            <div class="section">
                <h3>Operations Summary</h3>
                <table>
                    <tr><th>Operation</th><th>Total</th><th>Success Rate</th><th>Avg Duration</th></tr>
                    <tr><td>Downloads</td><td>#{summary.operations.downloads.total}</td><td>#{summary.operations.downloads.success_rate}%</td><td>#{summary.operations.downloads.avg_duration_ms}ms</td></tr>
                    <tr><td>Builds</td><td>#{summary.operations.builds.total}</td><td>#{summary.operations.builds.success_rate}%</td><td>#{summary.operations.builds.avg_duration_ms}ms</td></tr>
                    <tr><td>Deployments</td><td>#{summary.operations.deployments.total}</td><td>#{summary.operations.deployments.success_rate}%</td><td>#{summary.operations.deployments.avg_duration_ms}ms</td></tr>
                </table>
            </div>
            
            <div class="section">
                <h3>Active Operations</h3>
                #{format_active_spans_html(summary.active_spans)}
            </div>
        </div>
        
        <script>
            // Auto-refresh every 30 seconds
            setTimeout(() => location.reload(), 30000);
        </script>
    </body>
    </html>
    """
  end

  # Placeholder functions - would be implemented with real metrics storage
  defp get_system_uptime, do: elem(:erlang.statistics(:wall_clock), 0) |> div(1000)
  defp get_memory_health, do: %{used: 0, total: 0, percent: 0}
  defp get_load_average, do: 0.0
  defp determine_system_status, do: :ok
  defp get_operation_count(_op, _window \\ nil), do: 0
  defp get_success_rate(_op), do: 100.0
  defp get_avg_duration(_op), do: 0
  defp get_percentile(_metric, _percentile), do: 0
  defp get_requests_per_minute, do: 0
  defp get_avg_download_speed, do: 0.0
  defp get_avg_build_rate, do: 0.0
  defp get_sla_compliance(_op), do: 100.0
  defp get_total_errors, do: 0
  defp get_error_rate, do: 0.0
  defp get_top_errors(_limit), do: []
  defp get_error_count(_op), do: 0
  defp get_recent_errors(_limit), do: []

  defp format_status(:ok), do: "✅ HEALTHY"
  defp format_status(:warn), do: "⚠️  WARNING"
  defp format_status(:error), do: "❌ ERROR"
  defp format_status(_), do: "❓ UNKNOWN"

  defp format_uptime(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  defp format_memory(%{percent: percent}), do: "#{percent}%"
  defp format_memory(_), do: "N/A"

  defp format_load(load) when is_number(load), do: Float.round(load, 2)
  defp format_load(_), do: "N/A"

  defp format_operation_stats(stats) do
    "#{stats.total} total, #{stats.success_rate}% success, #{stats.avg_duration_ms}ms avg"
  end

  defp format_top_errors([]), do: "None"
  defp format_top_errors(errors) do
    errors |> Enum.take(3) |> Enum.map_join(", ", & &1.type)
  end

  defp format_active_spans([]), do: "║ No active operations                                                          ║"
  defp format_active_spans(spans) do
    spans
    |> Enum.take(5)
    |> Enum.map(fn span ->
      "║ #{span.operation}: #{span.id} (#{span.duration}ms)                                     ║"
    end)
    |> Enum.join("\n")
  end

  defp format_active_spans_html([]), do: "<p>No active operations</p>"
  defp format_active_spans_html(spans) do
    rows = Enum.map(spans, fn span ->
      "<tr><td>#{span.operation}</td><td>#{span.id}</td><td>#{span.duration}ms</td></tr>"
    end)
    
    "<table><tr><th>Operation</th><th>ID</th><th>Duration</th></tr>#{Enum.join(rows)}</table>"
  end

  defp clear_screen do
    IO.write("\e[H\e[2J")
  end
end