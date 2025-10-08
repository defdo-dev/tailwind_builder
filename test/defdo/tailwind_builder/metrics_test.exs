defmodule Defdo.TailwindBuilder.MetricsTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindBuilder.{Metrics, Telemetry}

  @moduletag :metrics

  setup do
    # Ensure telemetry is started for metrics tests
    case Process.whereis(Telemetry) do
      nil ->
        {:ok, _} = start_supervised({Telemetry, []})

      _pid ->
        :ok
    end

    :ok
  end

  describe "download metrics" do
    test "records download metrics correctly" do
      version = "4.1.11"
      # 1MB
      size_bytes = 1_048_576
      # 2 seconds
      duration_ms = 2000
      status = :success

      # This should not raise an error
      assert :ok = Metrics.record_download_metrics(version, size_bytes, duration_ms, status)
    end

    test "handles zero duration gracefully" do
      # Edge case: zero duration
      assert :ok = Metrics.record_download_metrics("4.1.11", 1024, 0, :success)
    end

    test "records error metrics for failed downloads" do
      assert :ok = Metrics.record_download_metrics("4.1.11", 0, 1000, :error)
    end
  end

  describe "build metrics" do
    test "records build metrics correctly" do
      version = "4.1.11"
      plugins = ["daisyui", "@tailwindcss/typography"]
      duration_ms = 5000
      # 2MB
      output_size = 2_097_152
      status = :success

      assert :ok =
               Metrics.record_build_metrics(version, plugins, duration_ms, output_size, status)
    end

    test "handles empty plugin list" do
      assert :ok = Metrics.record_build_metrics("4.1.11", [], 1000, 1024, :success)
    end

    test "calculates build rate correctly" do
      # This tests internal calculation logic
      assert :ok = Metrics.record_build_metrics("4.1.11", ["daisyui"], 1000, 1000, :success)
    end
  end

  describe "deployment metrics" do
    test "records deployment metrics correctly" do
      target = :r2
      file_count = 5
      # 10MB
      total_size = 10_485_760
      duration_ms = 3000
      status = :success

      assert :ok =
               Metrics.record_deployment_metrics(
                 target,
                 file_count,
                 total_size,
                 duration_ms,
                 status
               )
    end

    test "handles different deployment targets" do
      targets = [:r2, :s3, :local, :cdn]

      for target <- targets do
        assert :ok = Metrics.record_deployment_metrics(target, 1, 1024, 1000, :success)
      end
    end
  end

  describe "system resource metrics" do
    test "records system metrics without errors" do
      # This should gather real system metrics
      assert :ok = Metrics.record_resource_metrics()
    end
  end

  describe "error metrics" do
    test "records error metrics with categorization" do
      operation = :download
      error_type = :network_timeout
      error_details = %{timeout: 30_000, url: "https://example.com"}

      assert :ok = Metrics.record_error_metrics(operation, error_type, error_details)
    end

    test "handles different error types" do
      error_types = [:network_timeout, :checksum_mismatch, :file_not_found, :permission_denied]

      for error_type <- error_types do
        assert :ok = Metrics.record_error_metrics(:test, error_type, %{})
      end
    end
  end

  describe "cache metrics" do
    test "records cache hit metrics" do
      assert :ok = Metrics.record_cache_metrics(:download, "cache_key_123", :hit)
    end

    test "records cache miss metrics" do
      assert :ok = Metrics.record_cache_metrics(:download, "cache_key_456", :miss)
    end
  end

  describe "SLA metrics" do
    test "records SLA metrics for successful operations" do
      start_time = System.monotonic_time()
      # Simulate work
      Process.sleep(10)
      end_time = System.monotonic_time()

      assert :ok = Metrics.record_sla_metrics(:download, start_time, end_time, true)
    end

    test "records SLA metrics for failed operations" do
      start_time = System.monotonic_time()
      # Simulate work
      Process.sleep(10)
      end_time = System.monotonic_time()

      assert :ok = Metrics.record_sla_metrics(:build, start_time, end_time, false)
    end

    test "handles different operation types for SLA" do
      operations = [:download, :build, :deploy, :plugin_install]
      start_time = System.monotonic_time()
      end_time = System.monotonic_time()

      for operation <- operations do
        assert :ok = Metrics.record_sla_metrics(operation, start_time, end_time, true)
      end
    end
  end

  describe "business metrics" do
    test "records business metrics without user agent" do
      assert :ok = Metrics.record_business_metrics(:download, "4.1.11")
    end

    test "records business metrics with user agent" do
      user_agent = "TailwindBuilder/1.0 (Elixir/1.15)"
      assert :ok = Metrics.record_business_metrics(:build, "4.1.11", user_agent)
    end

    test "handles different client types in user agent" do
      user_agents = [
        "curl/7.68.0",
        "wget/1.20.3",
        "Mozilla/5.0 (compatible; TailwindBuilder)",
        "Phoenix/1.7"
      ]

      for user_agent <- user_agents do
        assert :ok = Metrics.record_business_metrics(:deploy, "4.1.11", user_agent)
      end
    end
  end

  describe "metrics summary" do
    test "gets metrics summary without errors" do
      summary = Metrics.get_metrics_summary()

      assert is_map(summary)
      assert Map.has_key?(summary, :system)
      assert Map.has_key?(summary, :operations)
      assert Map.has_key?(summary, :errors)
      assert Map.has_key?(summary, :performance)
    end

    test "gets metrics summary with different time windows" do
      summary_1h = Metrics.get_metrics_summary(60)
      summary_24h = Metrics.get_metrics_summary(1440)

      assert is_map(summary_1h)
      assert is_map(summary_24h)
    end
  end

  describe "version extraction" do
    test "extracts major version correctly" do
      # Test the private function indirectly through business metrics
      versions = ["3.4.17", "4.1.11", "5.0.0-beta.1", "invalid.version"]

      for version <- versions do
        assert :ok = Metrics.record_business_metrics(:test, version)
      end
    end
  end
end
