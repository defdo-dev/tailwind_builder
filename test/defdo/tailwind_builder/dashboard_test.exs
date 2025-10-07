defmodule Defdo.TailwindBuilder.DashboardTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindBuilder.{Dashboard, Telemetry}

  @moduletag :dashboard

  setup do
    # Ensure telemetry is started for dashboard tests
    case Process.whereis(Telemetry) do
      nil ->
        {:ok, _} = start_supervised({Telemetry, []})

      _pid ->
        :ok
    end

    :ok
  end

  describe "dashboard summary generation" do
    test "generates summary in default format" do
      summary = Dashboard.generate_summary(format: :raw)

      assert is_map(summary)
      assert Map.has_key?(summary, :timestamp)
      assert Map.has_key?(summary, :system_health)
      assert Map.has_key?(summary, :operations)
      assert Map.has_key?(summary, :performance)
      assert Map.has_key?(summary, :errors)
      assert Map.has_key?(summary, :active_spans)
    end

    test "generates summary in JSON format" do
      json_summary = Dashboard.generate_summary(format: :json)

      assert is_binary(json_summary)

      # Should be valid JSON
      {:ok, parsed} = Jason.decode(json_summary)
      assert is_map(parsed)
    end

    test "generates summary in text format" do
      text_summary = Dashboard.generate_summary(format: :text)

      assert is_binary(text_summary)
      assert String.contains?(text_summary, "TAILWIND BUILDER DASHBOARD")
      assert String.contains?(text_summary, "SYSTEM HEALTH")
      assert String.contains?(text_summary, "OPERATIONS SUMMARY")
    end

    test "generates summary in HTML format" do
      html_summary = Dashboard.generate_summary(format: :html)

      assert is_binary(html_summary)
      assert String.contains?(html_summary, "<!DOCTYPE html>")
      assert String.contains?(html_summary, "TailwindBuilder Dashboard")
      assert String.contains?(html_summary, "</html>")
    end

    test "accepts different time windows" do
      summary_30 = Dashboard.generate_summary(time_window_minutes: 30, format: :raw)
      summary_120 = Dashboard.generate_summary(time_window_minutes: 120, format: :raw)

      assert summary_30.time_window_minutes == 30
      assert summary_120.time_window_minutes == 120
    end
  end

  describe "system health monitoring" do
    test "gets system health indicators" do
      health = Dashboard.get_system_health()

      assert is_map(health)
      assert Map.has_key?(health, :telemetry_enabled)
      assert Map.has_key?(health, :active_operations)
      assert Map.has_key?(health, :system_uptime_seconds)
      assert Map.has_key?(health, :memory_usage)
      assert Map.has_key?(health, :process_count)
      assert Map.has_key?(health, :status)

      # Telemetry should be enabled in tests
      assert health.telemetry_enabled == true
      assert is_integer(health.active_operations)
      assert is_integer(health.system_uptime_seconds)
      assert is_integer(health.process_count)
      assert health.status in [:ok, :warn, :error]
    end
  end

  describe "operations summary" do
    test "gets operations summary" do
      ops_summary = Dashboard.get_operations_summary()

      assert is_map(ops_summary)
      assert Map.has_key?(ops_summary, :downloads)
      assert Map.has_key?(ops_summary, :builds)
      assert Map.has_key?(ops_summary, :deployments)

      # Each operation should have required metrics
      for operation <- [:downloads, :builds, :deployments] do
        op_data = Map.get(ops_summary, operation)
        assert Map.has_key?(op_data, :total)
        assert Map.has_key?(op_data, :success_rate)
        assert Map.has_key?(op_data, :avg_duration_ms)
        assert Map.has_key?(op_data, :last_24h)
      end
    end
  end

  describe "performance summary" do
    test "gets performance metrics" do
      perf_summary = Dashboard.get_performance_summary()

      assert is_map(perf_summary)
      assert Map.has_key?(perf_summary, :response_times)
      assert Map.has_key?(perf_summary, :throughput)
      assert Map.has_key?(perf_summary, :sla_compliance)

      # Response times should have percentiles
      response_times = perf_summary.response_times
      assert Map.has_key?(response_times, :p50)
      assert Map.has_key?(response_times, :p95)
      assert Map.has_key?(response_times, :p99)
    end
  end

  describe "error summary" do
    test "gets error summary" do
      error_summary = Dashboard.get_errors_summary()

      assert is_map(error_summary)
      assert Map.has_key?(error_summary, :total_errors)
      assert Map.has_key?(error_summary, :error_rate_percent)
      assert Map.has_key?(error_summary, :top_errors)
      assert Map.has_key?(error_summary, :errors_by_operation)
      assert Map.has_key?(error_summary, :recent_errors)

      # Error counts should be numeric
      assert is_number(error_summary.total_errors)
      assert is_number(error_summary.error_rate_percent)
      assert is_list(error_summary.top_errors)
      assert is_map(error_summary.errors_by_operation)
      assert is_list(error_summary.recent_errors)
    end
  end

  describe "dashboard export" do
    test "exports dashboard to JSON file" do
      temp_file = "/tmp/test_dashboard_#{:rand.uniform(10000)}.json"

      try do
        assert :ok = Dashboard.export_dashboard(temp_file, :json, silent: true)
        assert File.exists?(temp_file)

        # Verify content is valid JSON
        content = File.read!(temp_file)
        {:ok, _parsed} = Jason.decode(content)
      after
        File.rm(temp_file)
      end
    end

    test "exports dashboard to text file" do
      temp_file = "/tmp/test_dashboard_#{:rand.uniform(10000)}.txt"

      try do
        assert :ok = Dashboard.export_dashboard(temp_file, :text, silent: true)
        assert File.exists?(temp_file)

        # Verify content contains expected text
        content = File.read!(temp_file)
        assert String.contains?(content, "TAILWIND BUILDER DASHBOARD")
      after
        File.rm(temp_file)
      end
    end

    test "handles export errors gracefully" do
      invalid_path = "/invalid/path/dashboard.json"

      assert {:error, _reason} = Dashboard.export_dashboard(invalid_path, :json, silent: true)
    end
  end

  describe "formatting functions" do
    test "formats system status correctly" do
      # Test via text dashboard generation
      summary = Dashboard.generate_summary(format: :text)

      # Should contain status indicators
      assert String.contains?(summary, "Status:")
    end

    test "formats uptime correctly" do
      # Test that uptime formatting works
      summary = Dashboard.generate_summary(format: :text)

      assert String.contains?(summary, "Uptime:")
    end

    test "formats active spans" do
      # Create some active spans
      span_id1 = Telemetry.start_span(:download, %{version: "4.1.11"})
      span_id2 = Telemetry.start_span(:build, %{version: "3.4.17"})

      try do
        summary = Dashboard.generate_summary(format: :text)

        # Should show active operations
        assert String.contains?(summary, "ACTIVE OPERATIONS")
      after
        Telemetry.end_span(span_id1)
        Telemetry.end_span(span_id2)
      end
    end
  end

  describe "HTML dashboard" do
    test "generates valid HTML structure" do
      html = Dashboard.generate_summary(format: :html)

      # Basic HTML structure checks
      assert String.contains?(html, "<html>")
      assert String.contains?(html, "<head>")
      assert String.contains?(html, "<body>")
      assert String.contains?(html, "</html>")

      # CSS and styling
      assert String.contains?(html, "<style>")
      assert String.contains?(html, "font-family: monospace")

      # JavaScript auto-refresh
      assert String.contains?(html, "<script>")
      assert String.contains?(html, "location.reload()")
    end

    test "includes telemetry data in HTML" do
      html = Dashboard.generate_summary(format: :html)

      # Should contain data sections
      assert String.contains?(html, "System Health")
      assert String.contains?(html, "Operations Summary")
      assert String.contains?(html, "Active Operations")
    end
  end
end
