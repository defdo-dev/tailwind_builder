defmodule Defdo.TailwindBuilder.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start telemetry system first for comprehensive monitoring
      {Defdo.TailwindBuilder.Telemetry, []}

      # Future workers can be added here
      # {Defdo.TailwindBuilder.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Defdo.TailwindBuilder.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = result ->
        # Initialize telemetry metrics collection
        schedule_metrics_collection()
        result

      error ->
        error
    end
  end

  defp schedule_metrics_collection do
    # Schedule periodic system metrics collection
    # Every 30 seconds
    Process.send_after(self(), :collect_system_metrics, 30_000)
  end

  def handle_info(:collect_system_metrics, state) do
    Defdo.TailwindBuilder.Metrics.record_resource_metrics()

    # Schedule next collection
    Process.send_after(self(), :collect_system_metrics, 30_000)
    {:noreply, state}
  end
end
