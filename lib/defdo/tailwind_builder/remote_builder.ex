defmodule Defdo.TailwindBuilder.RemoteBuilder do
  @moduledoc """
  Client for distributed TailwindCSS compilation.

  This module provides a seamless interface for requesting builds from
  a distributed network of compilation nodes when local compilation
  is not possible or fails.

  ## Usage

      # Request remote build
      {:ok, result} = RemoteBuilder.build_remote([
        version: "4.1.13",
        target_arch: "linux-x64",
        plugins: [%{name: "daisyui", version: "^5.1.13"}],
        source_path: "/tmp/tailwind-source"
      ])

      # Check if remote build is available for architecture
      RemoteBuilder.supports_architecture?("linux-x64")  # true

  ## Configuration

      config :tailwind_builder, :remote_builder,
        coordinator_url: "https://builds.tailwindbuilder.com",
        api_key: "your-api-key",
        timeout: 300_000,  # 5 minutes
        poll_interval: 5_000  # 5 seconds
  """

  require Logger
  alias Defdo.TailwindBuilder.Telemetry

  @default_timeout 300_000  # 5 minutes
  @default_poll_interval 5_000  # 5 seconds

  @doc """
  Build TailwindCSS using remote compilation nodes
  """
  def build_remote(opts) do
    opts = validate_remote_build_options(opts)

    Telemetry.track_event(:remote_build, :start, %{
      version: opts[:version],
      target_arch: opts[:target_arch],
      coordinator: coordinator_url()
    })

    with {:coordinator_available, true} <- {:coordinator_available, coordinator_available?()},
         {:create_build_request, {:ok, build_request}} <- {:create_build_request, create_build_request(opts)},
         {:submit_build, {:ok, build_id}} <- {:submit_build, submit_build_request(build_request)},
         {:wait_completion, {:ok, build_result}} <- {:wait_completion, wait_for_build_completion(build_id, opts)},
         {:download_binary, {:ok, binary_path}} <- {:download_binary, download_build_binary(build_result, opts)} do

      result = %{
        version: opts[:version],
        target_arch: opts[:target_arch],
        compilation_method: :remote,
        build_id: build_id,
        binary_path: binary_path,
        build_time_ms: build_result["build_time_seconds"] * 1000,
        node_id: build_result["node_id"]
      }

      Telemetry.track_event(:remote_build, :success, result)
      {:ok, result}
    else
      {step, error} ->
        Logger.error("Remote build failed at step #{step}: #{inspect(error)}")
        Telemetry.track_event(:remote_build, :error, %{step: step, error: inspect(error)})
        {:error, {step, error}}
    end
  end

  @doc """
  Check if the build coordinator is available
  """
  def coordinator_available? do
    case Req.get("#{coordinator_url()}/api/v1/health", receive_timeout: 5000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  catch
    _ -> false
  end

  @doc """
  Get supported architectures from the coordinator
  """
  def supported_architectures do
    case Req.get("#{coordinator_url()}/api/v1/architectures") do
      {:ok, %{status: 200, body: %{"architectures" => architectures}}} ->
        {:ok, architectures}
      error ->
        Logger.warning("Failed to fetch supported architectures: #{inspect(error)}")
        {:error, :coordinator_unavailable}
    end
  end

  @doc """
  Check if an architecture is supported by remote nodes
  """
  def supports_architecture?(target_arch) do
    case supported_architectures() do
      {:ok, architectures} -> target_arch in architectures
      {:error, _} -> false
    end
  end

  @doc """
  Get current build queue status
  """
  def queue_status do
    case Req.get("#{coordinator_url()}/api/v1/queue/status") do
      {:ok, %{status: 200, body: status}} -> {:ok, status}
      error -> {:error, error}
    end
  end

  ## Private Functions

  defp validate_remote_build_options(opts) do
    required_keys = [:version, :target_arch, :source_path]

    Enum.each(required_keys, fn key ->
      unless Keyword.has_key?(opts, key) do
        raise ArgumentError, "Missing required option: #{key}"
      end
    end)

    # Validate target architecture format
    target_arch = opts[:target_arch]
    unless String.match?(target_arch, ~r/^[a-z]+-[a-z0-9]+$/) do
      raise ArgumentError, "Invalid target architecture format: #{target_arch}"
    end

    opts
  end

  defp create_build_request(opts) do
    # Calculate source checksum for caching
    source_checksum = calculate_source_checksum(opts)

    build_request = %{
      version: opts[:version],
      target_arch: opts[:target_arch],
      plugins: normalize_plugins(opts[:plugins] || []),
      config: opts[:config] || %{},
      source_checksum: source_checksum,
      priority: opts[:priority] || "normal",
      metadata: %{
        client_version: Application.spec(:tailwind_builder, :vsn),
        requested_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    {:ok, build_request}
  end

  defp submit_build_request(build_request) do
    Logger.info("Submitting remote build request for #{build_request.version} (#{build_request.target_arch})")

    headers = [
      {"authorization", "Bearer #{api_key()}"},
      {"content-type", "application/json"}
    ]

    case Req.post("#{coordinator_url()}/api/v1/builds", json: build_request, headers: headers) do
      {:ok, %{status: 200, body: %{"build_id" => build_id} = response}} ->
        Logger.info("Build submitted successfully: #{build_id}")
        Logger.info("Queue position: #{response["queue_position"]}, ETA: #{response["estimated_time"]}s")
        {:ok, build_id}

      {:ok, %{status: 409, body: %{"build_id" => build_id}}} ->
        Logger.info("Build already exists (cache hit): #{build_id}")
        {:ok, build_id}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp wait_for_build_completion(build_id, opts) do
    timeout = opts[:timeout] || @default_timeout
    poll_interval = opts[:poll_interval] || @default_poll_interval
    start_time = System.monotonic_time()

    Logger.info("Waiting for build completion: #{build_id}")

    wait_loop(build_id, start_time, timeout, poll_interval)
  end

  defp wait_loop(build_id, start_time, timeout, poll_interval) do
    elapsed = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

    if elapsed >= timeout do
      {:error, :timeout}
    else
      case check_build_status(build_id) do
        {:ok, %{"status" => "completed"} = result} ->
          Logger.info("Build completed successfully: #{build_id}")
          {:ok, result}

        {:ok, %{"status" => "failed", "error" => error}} ->
          Logger.error("Build failed: #{build_id} - #{error}")
          {:error, {:build_failed, error}}

        {:ok, %{"status" => status, "progress" => progress}} ->
          Logger.info("Build #{status}: #{build_id} (#{progress}%)")
          Process.sleep(poll_interval)
          wait_loop(build_id, start_time, timeout, poll_interval)

        {:error, reason} ->
          Logger.warning("Failed to check build status: #{inspect(reason)}")
          Process.sleep(poll_interval)
          wait_loop(build_id, start_time, timeout, poll_interval)
      end
    end
  end

  defp check_build_status(build_id) do
    case Req.get("#{coordinator_url()}/api/v1/builds/#{build_id}") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      error -> {:error, error}
    end
  end

  defp download_build_binary(build_result, opts) do
    binary_url = build_result["binary_url"]
    target_arch = build_result["target_arch"]

    # Create output directory
    output_dir = Path.join(opts[:source_path], "dist")
    File.mkdir_p!(output_dir)

    # Determine output filename
    output_filename = case target_arch do
      "linux-x64" -> "tailwindcss-linux-x64"
      "linux-arm64" -> "tailwindcss-linux-arm64"
      "darwin-x64" -> "tailwindcss-macos-x64"
      "darwin-arm64" -> "tailwindcss-macos-arm64"
      "win32-x64" -> "tailwindcss-windows-x64.exe"
      _ -> "tailwindcss-#{target_arch}"
    end

    output_path = Path.join(output_dir, output_filename)

    Logger.info("Downloading binary from: #{binary_url}")

    case Req.get(binary_url, into: File.stream!(output_path)) do
      {:ok, %{status: 200}} ->
        # Verify download
        case File.stat(output_path) do
          {:ok, %{size: size}} when size > 0 ->
            File.chmod!(output_path, 0o755)  # Make executable
            Logger.info("Binary downloaded successfully: #{output_path} (#{size} bytes)")
            {:ok, output_path}
          {:ok, %{size: 0}} ->
            File.rm!(output_path)
            {:error, :empty_download}
          {:error, reason} ->
            {:error, {:download_verification_failed, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:download_failed, status}}

      {:error, reason} ->
        {:error, {:download_error, reason}}
    end
  end

  defp calculate_source_checksum(opts) do
    # Create a hash of version + plugins + config for caching
    content = %{
      version: opts[:version],
      plugins: normalize_plugins(opts[:plugins] || []),
      config: opts[:config] || %{}
    }

    content
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_plugins(plugins) when is_list(plugins) do
    Enum.map(plugins, fn
      %{name: name, version: version} -> %{name: name, version: version}
      %{"name" => name, "version" => version} -> %{name: name, version: version}
      {name, version} -> %{name: to_string(name), version: to_string(version)}
      name when is_binary(name) -> %{name: name, version: "latest"}
      other -> other
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp normalize_plugins(_plugins), do: []

  defp coordinator_url do
    Application.get_env(:tailwind_builder, :remote_builder)[:coordinator_url] ||
      raise "Missing coordinator_url configuration"
  end

  defp api_key do
    Application.get_env(:tailwind_builder, :remote_builder)[:api_key] ||
      System.get_env("TAILWIND_BUILDER_API_KEY") ||
      raise "Missing API key for remote builds"
  end
end