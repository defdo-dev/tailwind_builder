defmodule Defdo.TailwindBuilder.BuildMonitor do
  @moduledoc """
  Real-time build progress monitoring system.

  Provides live updates during TailwindCSS build process using telemetry events
  and GenServer for real-time communication.

  ## Usage

      # Start monitoring a build
      {:ok, monitor_pid} = BuildMonitor.start_monitoring(self())

      # Execute build (will send progress updates to monitor_pid)
      TailwindBuilder.build("4.1.14", "/path/to/dir")

      # Handle progress messages in your process
      # def handle_info({:build_progress, event}, state) do
      #   IO.puts("Build progress: \#{event.message}")
      #   {:noreply, state}
      # end
  """

  use GenServer
  require Logger

  @doc """
  Start monitoring build progress and send updates to subscriber_pid
  """
  def start_monitoring(subscriber_pid) when is_pid(subscriber_pid) do
    GenServer.start_link(__MODULE__, %{subscriber: subscriber_pid})
  end

  @doc """
  Stop monitoring
  """
  def stop_monitoring(monitor_pid) when is_pid(monitor_pid) do
    GenServer.stop(monitor_pid)
  end

  ## GenServer Callbacks

  @impl true
  def init(%{subscriber: subscriber_pid}) do
    # Subscribe to all tailwind builder telemetry events
    :telemetry.attach_many(
      "build-monitor-#{inspect(self())}",
      [
        [:tailwind_builder, :build, :step, :start],
        [:tailwind_builder, :build, :step, :stop],
        [:tailwind_builder, :build, :compilation_start],
        [:tailwind_builder, :build, :compilation_success],
        [:tailwind_builder, :build, :compilation_error]
      ],
      &handle_telemetry_event/4,
      %{monitor_pid: self()}
    )

    Logger.info("[BUILD_MONITOR] Started monitoring for #{inspect(subscriber_pid)}")

    {:ok,
     %{
       subscriber: subscriber_pid,
       current_step: nil,
       start_time: System.monotonic_time(),
       steps_completed: 0,
       total_steps: nil
     }}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach("build-monitor-#{inspect(self())}")
    Logger.info("[BUILD_MONITOR] Stopped monitoring for #{inspect(state.subscriber)}")
    :ok
  end

  @impl true
  def handle_info({:telemetry_event, event_data}, state) do
    # Send formatted progress update to subscriber
    send(state.subscriber, {:build_progress, event_data})
    {:noreply, update_state(state, event_data)}
  end

  ## Telemetry Event Handler

  def handle_telemetry_event(event_name, measurements, metadata, %{monitor_pid: monitor_pid}) do
    event_data = %{
      event: event_name,
      measurements: measurements,
      metadata: metadata,
      timestamp: System.system_time(:millisecond)
    }

    # Format the event data for easier consumption
    formatted_event = format_event(event_data)

    send(monitor_pid, {:telemetry_event, formatted_event})
  end

  ## Private Functions

  defp format_event(
         %{event: [:tailwind_builder, :build, :step, :start], metadata: metadata} = event
       ) do
    %{
      type: :step_start,
      step: metadata.step,
      version: metadata.version,
      timestamp: event.timestamp,
      message: "Starting: #{metadata.step}"
    }
  end

  defp format_event(
         %{event: [:tailwind_builder, :build, :step, :stop], metadata: metadata} = event
       ) do
    %{
      type: :step_complete,
      step: metadata.step,
      version: metadata.version,
      result: metadata.result,
      timestamp: event.timestamp,
      message:
        case metadata.result do
          :success -> "✓ Completed: #{metadata.step}"
          :error -> "✗ Failed: #{metadata.step}"
          _ -> "◦ Finished: #{metadata.step}"
        end
    }
  end

  defp format_event(
         %{event: [:tailwind_builder, :build, :compilation_start], metadata: metadata} = event
       ) do
    %{
      type: :compilation_start,
      version: metadata.version,
      compilation_method: metadata.compilation_method,
      debug: metadata.debug,
      timestamp: event.timestamp,
      message:
        "🏗️  Starting compilation for Tailwind v#{metadata.version} (#{metadata.compilation_method})"
    }
  end

  defp format_event(
         %{event: [:tailwind_builder, :build, :compilation_success], metadata: metadata} = event
       ) do
    duration_sec = metadata.duration_ms / 1000

    %{
      type: :compilation_success,
      version: metadata.version,
      compilation_method: metadata.compilation_method,
      duration_ms: metadata.duration_ms,
      timestamp: event.timestamp,
      message: "🎉 Compilation successful! (#{duration_sec}s)"
    }
  end

  defp format_event(
         %{event: [:tailwind_builder, :build, :compilation_error], metadata: metadata} = event
       ) do
    %{
      type: :compilation_error,
      version: metadata.version,
      error: metadata.error,
      timestamp: event.timestamp,
      message: "💥 Compilation failed: #{metadata.error}"
    }
  end

  defp format_event(event) do
    %{
      type: :unknown,
      raw_event: event,
      timestamp: event.timestamp,
      message: "Unknown event: #{inspect(event.event)}"
    }
  end

  defp update_state(state, %{type: :step_start} = event) do
    %{
      state
      | current_step: event.step,
        total_steps: state.total_steps || estimate_total_steps(event.version)
    }
  end

  defp update_state(state, %{type: :step_complete}) do
    %{state | steps_completed: state.steps_completed + 1, current_step: nil}
  end

  defp update_state(state, _event), do: state

  defp estimate_total_steps(version) when is_binary(version) do
    case String.starts_with?(version, "4.") do
      # v4: pnpm install, oxide build, workspace build, bun build
      true -> 4
      # v3: npm install (root), npm build (root), npm install (standalone), npm build (standalone)
      false -> 4
    end
  end

  ## Public API for Progress Information

  @doc """
  Get current build progress information
  """
  def get_progress(monitor_pid) when is_pid(monitor_pid) do
    GenServer.call(monitor_pid, :get_progress)
  end

  @impl true
  def handle_call(:get_progress, _from, state) do
    progress = %{
      current_step: state.current_step,
      steps_completed: state.steps_completed,
      total_steps: state.total_steps,
      progress_percentage: calculate_percentage(state.steps_completed, state.total_steps),
      elapsed_time_ms: System.monotonic_time() - state.start_time
    }

    {:reply, progress, state}
  end

  defp calculate_percentage(_completed, nil), do: 0

  defp calculate_percentage(completed, total) when total > 0 do
    round(completed / total * 100)
  end

  defp calculate_percentage(_, _), do: 0
end
