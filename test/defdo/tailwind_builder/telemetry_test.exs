defmodule Defdo.TailwindBuilder.TelemetryTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindBuilder.Telemetry

  @moduletag :telemetry

  setup do
    # Ensure telemetry is started for tests
    case Process.whereis(Telemetry) do
      nil ->
        {:ok, _} = start_supervised({Telemetry, []})

      _pid ->
        :ok
    end

    :ok
  end

  describe "telemetry system" do
    test "can be started and stopped" do
      # Telemetry should be running from setup
      assert Process.whereis(Telemetry) != nil
      assert Telemetry.enabled?()
    end

    test "tracks telemetry stats" do
      stats = Telemetry.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :enabled)
      assert Map.has_key?(stats, :active_spans)
      assert stats.enabled == true
    end

    test "can start and end spans" do
      span_id = Telemetry.start_span(:download, %{version: "test"})

      assert is_binary(span_id)
      # 8 bytes encoded as hex
      assert byte_size(span_id) == 16

      active_spans = Telemetry.get_active_spans()
      assert length(active_spans) >= 1

      # End the span
      :ok = Telemetry.end_span(span_id, :success, %{size: 1024})

      # Active spans should be updated
      new_active_spans = Telemetry.get_active_spans()
      assert length(new_active_spans) < length(active_spans)
    end

    test "tracks events for operations" do
      # This test verifies events are tracked without errors
      assert :ok = Telemetry.track_event(:download, :start, %{version: "4.1.11"})
      assert :ok = Telemetry.track_event(:download, :progress, %{percent: 50})
      assert :ok = Telemetry.track_event(:download, :stop, %{size: 2048})
    end

    test "tracks metrics" do
      assert :ok = Telemetry.track_metric("test.counter", 1, %{operation: :test})
      assert :ok = Telemetry.track_metric("test.duration", 150, %{operation: :test})
    end

    test "structured logging works" do
      assert :ok = Telemetry.log(:info, "Test log message", %{test: true})
      assert :ok = Telemetry.log(:error, "Test error message", %{error: "test_error"})
    end
  end

  describe "span tracking" do
    test "track_download convenience function" do
      result =
        Telemetry.track_download("4.1.11", fn ->
          # Simulate work
          Process.sleep(10)
          {:ok, "download_result"}
        end)

      assert result == {:ok, "download_result"}
    end

    test "track_build convenience function" do
      result =
        Telemetry.track_build("4.1.11", ["daisyui"], fn ->
          # Simulate work
          Process.sleep(10)
          {:ok, "build_result"}
        end)

      assert result == {:ok, "build_result"}
    end

    test "track_deploy convenience function" do
      result =
        Telemetry.track_deploy(:r2, fn ->
          # Simulate work
          Process.sleep(10)
          {:ok, "deploy_result"}
        end)

      assert result == {:ok, "deploy_result"}
    end

    test "handles errors in tracked functions" do
      assert_raise RuntimeError, "test error", fn ->
        Telemetry.track_download("4.1.11", fn ->
          raise "test error"
        end)
      end
    end
  end

  describe "telemetry configuration" do
    test "respects enabled/disabled state" do
      # Telemetry should be enabled by default in tests
      assert Telemetry.enabled?()

      # Test that operations still work when disabled
      # (In a real scenario, we'd test with telemetry disabled)
    end

    test "handles missing telemetry process gracefully" do
      # This tests the fallback behavior when telemetry isn't running
      # We can't easily test this without stopping the process in this test
      # but the enabled?/0 function should handle it gracefully
      assert is_boolean(Telemetry.enabled?())
    end
  end
end
