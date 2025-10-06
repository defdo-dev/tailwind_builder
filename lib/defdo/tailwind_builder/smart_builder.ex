defmodule Defdo.TailwindBuilder.SmartBuilder do
  @moduledoc """
  Smart builder that automatically falls back to remote compilation
  when local compilation is not possible.

  This module provides intelligent build strategy selection:
  1. Try local native compilation first
  2. Fallback to remote compilation if local fails
  3. Provide progress monitoring for both strategies

  ## Usage

      # Automatic strategy selection
      {:ok, result} = SmartBuilder.build([
        version: "4.1.13",
        source_path: "/tmp/tailwind-source",
        target_arch: "linux-x64",  # Optional - triggers remote if not native
        plugins: ["daisyui"]
      ])

      # Force specific strategy
      {:ok, result} = SmartBuilder.build([
        version: "4.1.13",
        source_path: "/tmp/tailwind-source",
        strategy: :remote_only
      ])
  """

  require Logger
  alias Defdo.TailwindBuilder.{Builder, RemoteBuilder, GitHubBuilder, Core, Telemetry}

  @doc """
  Smart build with automatic strategy selection
  """
  def build(opts \\ []) do
    opts = validate_build_options(opts)
    strategy = determine_build_strategy(opts)

    Telemetry.track_event(:smart_build, :start, %{
      version: opts[:version],
      target_arch: opts[:target_arch],
      strategy: strategy
    })

    case execute_build_strategy(strategy, opts) do
      {:ok, result} ->
        result = Map.put(result, :strategy_used, strategy)
        Telemetry.track_event(:smart_build, :success, result)
        {:ok, result}

      {:error, reason} ->
        Telemetry.track_event(:smart_build, :error, %{strategy: strategy, error: inspect(reason)})
        handle_build_failure(strategy, reason, opts)
    end
  end

  @doc """
  Check what build strategy would be used for given options
  """
  def determine_build_strategy(opts) do
    strategy = opts[:strategy]
    target_arch = opts[:target_arch]
    host_arch = Core.get_host_architecture()

    case strategy do
      :local_only -> :local
      :remote_only -> :remote
      :github_actions -> :github
      nil -> auto_select_strategy(target_arch, host_arch)
      _ -> raise ArgumentError, "Invalid strategy: #{strategy}"
    end
  end

  @doc """
  Get available build capabilities
  """
  def build_capabilities do
    host_arch = Core.get_host_architecture()
    local_capabilities = get_local_capabilities()
    remote_capabilities = get_remote_capabilities()

    %{
      host_architecture: host_arch,
      local: local_capabilities,
      remote: remote_capabilities,
      recommended_strategy: %{
        native: :local,
        cross_platform: :remote,
        github_actions: :github
      }
    }
  end

  ## Private Functions

  defp validate_build_options(opts) do
    required_keys = [:version, :source_path]

    Enum.each(required_keys, fn key ->
      unless Keyword.has_key?(opts, key) do
        raise ArgumentError, "Missing required option: #{key}"
      end
    end)

    opts
  end

  defp auto_select_strategy(target_arch, host_arch) do
    cond do
      # No target specified - always local
      is_nil(target_arch) ->
        :local

      # Target matches host - prefer local
      target_arch == host_arch ->
        :local

      # Cross-compilation requested - use remote (we removed cross-compilation)
      true ->
        :remote
    end
  end


  defp execute_build_strategy(:local, opts) do
    Logger.info("Building locally (native compilation)")
    Builder.compile(opts)
  end

  defp execute_build_strategy(:remote, opts) do
    Logger.info("Building remotely (distributed compilation)")
    RemoteBuilder.build_remote(opts)
  end

  defp execute_build_strategy(:github, opts) do
    Logger.info("Building with GitHub Actions")
    GitHubBuilder.trigger_build(opts)
  end


  defp handle_build_failure(:local, reason, opts) do
    if RemoteBuilder.coordinator_available?() and opts[:auto_fallback] != false do
      Logger.info("Local build failed, attempting remote fallback")
      opts_with_remote = Keyword.put(opts, :strategy, :remote)
      build(opts_with_remote)
    else
      {:error, reason}
    end
  end

  defp handle_build_failure(:remote, reason, _opts) do
    {:error, reason}
  end


  defp get_local_capabilities do
    host_arch = Core.get_host_architecture()

    %{
      native_architecture: host_arch,
      supported_versions: ["3.x", "4.x"],
      cross_compilation: false,  # We removed this
      estimated_build_time: %{
        "v3" => "60s",
        "v4" => "90s"
      }
    }
  end

  defp get_remote_capabilities do
    case RemoteBuilder.supported_architectures() do
      {:ok, architectures} ->
        %{
          available: true,
          supported_architectures: architectures,
          estimated_build_time: %{
            "v3" => "120s",
            "v4" => "180s"
          },
          coordinator_status: :available
        }

      {:error, _} ->
        %{
          available: false,
          coordinator_status: :unavailable
        }
    end
  end
end