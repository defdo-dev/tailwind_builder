defmodule Defdo.TailwindBuilder.GitHubBuilder do
  @moduledoc """
  GitHub Actions integration for distributed TailwindCSS compilation.

  This module provides integration with GitHub Actions to trigger remote builds
  through the Workflow Dispatch API. It allows the admin interface to submit
  build requests that are executed on GitHub's infrastructure.

  ## Configuration

  Set these environment variables or application config:

      GITHUB_TOKEN=ghp_your_personal_access_token
      GITHUB_REPO_OWNER=your-username
      GITHUB_REPO_NAME=tailwind-builder
      GITHUB_WORKFLOW_FILE=distributed-build.yml

  ## Usage

      # Trigger a build for specific architecture
      {:ok, build_id} = GitHubBuilder.trigger_build(%{
        version: "4.1.14",
        plugins: ["daisyui_v5"],
        target_arch: "linux-x64",
        callback_url: "https://your-app.com/api/builds/callback"
      })

      # Check build status
      {:ok, status} = GitHubBuilder.get_build_status(build_id)

      # Download completed binary
      {:ok, binary_url} = GitHubBuilder.get_binary_download_url(build_id)
  """

  require Logger
  alias Defdo.TailwindBuilder.Telemetry

  @github_api_url "https://api.github.com"
  @workflow_file "distributed-build.yml"

  @doc """
  Trigger a GitHub Actions build workflow
  """
  def trigger_build(opts \\ []) do
    with {:ok, config} <- get_github_config(),
         {:ok, build_id} <- generate_build_id(),
         {:ok, workflow_inputs} <- prepare_workflow_inputs(opts, build_id),
         {:ok, response} <- dispatch_workflow(config, workflow_inputs) do
      Telemetry.track_event(:github_build, :triggered, %{
        build_id: build_id,
        version: opts[:version],
        target_arch: opts[:target_arch]
      })

      {:ok,
       %{
         build_id: build_id,
         github_run_id: response["run_id"],
         status: :queued,
         triggered_at: DateTime.utc_now()
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to trigger GitHub build: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get the status of a GitHub Actions build
  """
  def get_build_status(build_id) when is_binary(build_id) do
    with {:ok, config} <- get_github_config(),
         {:ok, run_id} <- find_run_by_build_id(config, build_id),
         {:ok, run_data} <- fetch_workflow_run(config, run_id) do
      status = parse_github_status(run_data["status"], run_data["conclusion"])

      {:ok,
       %{
         build_id: build_id,
         github_run_id: run_id,
         status: status,
         started_at: run_data["run_started_at"],
         updated_at: run_data["updated_at"],
         html_url: run_data["html_url"]
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get download URL for completed binary
  """
  def get_binary_download_url(build_id) when is_binary(build_id) do
    with {:ok, config} <- get_github_config(),
         {:ok, run_id} <- find_run_by_build_id(config, build_id),
         {:ok, artifacts} <- fetch_workflow_artifacts(config, run_id),
         {:ok, artifact} <- find_binary_artifact(artifacts) do
      {:ok,
       %{
         download_url: artifact["archive_download_url"],
         artifact_name: artifact["name"],
         size_bytes: artifact["size_in_bytes"],
         expires_at: artifact["expires_at"]
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List all recent builds with their status
  """
  def list_recent_builds(limit \\ 20) do
    with {:ok, config} <- get_github_config(),
         {:ok, runs} <- fetch_recent_workflow_runs(config, limit) do
      builds =
        Enum.map(runs, fn run ->
          build_id = extract_build_id_from_run(run)
          status = parse_github_status(run["status"], run["conclusion"])

          %{
            build_id: build_id,
            github_run_id: run["id"],
            status: status,
            created_at: run["created_at"],
            updated_at: run["updated_at"],
            html_url: run["html_url"]
          }
        end)

      {:ok, builds}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancel a running build
  """
  def cancel_build(build_id) when is_binary(build_id) do
    with {:ok, config} <- get_github_config(),
         {:ok, run_id} <- find_run_by_build_id(config, build_id),
         {:ok, _response} <- cancel_workflow_run(config, run_id) do
      Telemetry.track_event(:github_build, :cancelled, %{build_id: build_id})
      {:ok, :cancelled}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  ## Private Functions

  defp get_github_config do
    config = %{
      token: get_config_value(:github_token),
      repo_owner: get_config_value(:github_repo_owner),
      repo_name: get_config_value(:github_repo_name),
      workflow_file: get_config_value(:github_workflow_file, @workflow_file)
    }

    case Enum.find(config, fn {_key, value} -> is_nil(value) end) do
      nil -> {:ok, config}
      {key, _} -> {:error, "Missing GitHub configuration: #{key}"}
    end
  end

  defp get_config_value(key, default \\ nil) do
    env_key =
      case key do
        :github_token -> "GITHUB_TOKEN"
        :github_repo_owner -> "GITHUB_REPO_OWNER"
        :github_repo_name -> "GITHUB_REPO_NAME"
        :github_workflow_file -> "GITHUB_WORKFLOW_FILE"
        _ -> key |> Atom.to_string() |> String.upcase()
      end

    System.get_env(env_key) ||
      Application.get_env(:tailwind_builder, key) ||
      default
  end

  defp generate_build_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    {:ok, "build-#{timestamp}-#{random}"}
  end

  defp prepare_workflow_inputs(opts, build_id) do
    inputs = %{
      "version" => opts[:version] || "4.1.14",
      "plugins" => Jason.encode!(opts[:plugins] || []),
      "target_arch" => opts[:target_arch] || "auto",
      "build_id" => build_id,
      "callback_url" => opts[:callback_url]
    }

    {:ok, inputs}
  end

  defp dispatch_workflow(config, inputs) do
    url =
      "#{@github_api_url}/repos/#{config.repo_owner}/#{config.repo_name}/actions/workflows/#{config.workflow_file}/dispatches"

    headers = [
      {"Authorization", "Bearer #{config.token}"},
      {"Accept", "application/vnd.github.v3+json"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        "ref" => "main",
        "inputs" => inputs
      })

    case Req.post(url, body: body, headers: headers) do
      {:ok, %Req.Response{status: 204}} ->
        # Workflow dispatch doesn't return run_id immediately
        # We'll need to find it by build_id later
        {:ok, %{"run_id" => nil}}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("GitHub API error #{status}: #{inspect(body)}")
        {:error, "GitHub API error: #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp find_run_by_build_id(config, build_id) do
    # GitHub doesn't provide direct lookup, so we search recent runs
    with {:ok, runs} <- fetch_recent_workflow_runs(config, 50) do
      run =
        Enum.find(runs, fn run ->
          extract_build_id_from_run(run) == build_id
        end)

      case run do
        nil -> {:error, "Build not found: #{build_id}"}
        run -> {:ok, run["id"]}
      end
    end
  end

  defp extract_build_id_from_run(run) do
    # Extract build_id from workflow run inputs or name
    # This assumes the build_id is stored in the run somehow
    case get_in(run, ["workflow_run", "inputs", "build_id"]) do
      nil ->
        # Fallback: try to extract from run name or other metadata
        "unknown-#{run["id"]}"

      build_id ->
        build_id
    end
  end

  defp fetch_workflow_run(config, run_id) do
    url =
      "#{@github_api_url}/repos/#{config.repo_owner}/#{config.repo_name}/actions/runs/#{run_id}"

    headers = [
      {"Authorization", "Bearer #{config.token}"},
      {"Accept", "application/vnd.github.v3+json"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, "GitHub API error: #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp fetch_recent_workflow_runs(config, limit) do
    url =
      "#{@github_api_url}/repos/#{config.repo_owner}/#{config.repo_name}/actions/workflows/#{config.workflow_file}/runs"

    headers = [
      {"Authorization", "Bearer #{config.token}"},
      {"Accept", "application/vnd.github.v3+json"}
    ]

    params = %{"per_page" => limit, "status" => "all"}

    case Req.get(url, headers: headers, params: params) do
      {:ok, %Req.Response{status: 200, body: %{"workflow_runs" => runs}}} ->
        {:ok, runs}

      {:ok, %Req.Response{status: status}} ->
        {:error, "GitHub API error: #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp fetch_workflow_artifacts(config, run_id) do
    url =
      "#{@github_api_url}/repos/#{config.repo_owner}/#{config.repo_name}/actions/runs/#{run_id}/artifacts"

    headers = [
      {"Authorization", "Bearer #{config.token}"},
      {"Accept", "application/vnd.github.v3+json"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %Req.Response{status: 200, body: %{"artifacts" => artifacts}}} ->
        {:ok, artifacts}

      {:ok, %Req.Response{status: status}} ->
        {:error, "GitHub API error: #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp find_binary_artifact(artifacts) do
    # Look for artifacts that contain compiled binaries
    binary_artifact =
      Enum.find(artifacts, fn artifact ->
        name = artifact["name"]

        String.contains?(name, "tailwindcss") and
          (String.contains?(name, "linux") or String.contains?(name, "darwin") or
             String.contains?(name, "win32"))
      end)

    case binary_artifact do
      nil -> {:error, "Binary artifact not found"}
      artifact -> {:ok, artifact}
    end
  end

  defp cancel_workflow_run(config, run_id) do
    url =
      "#{@github_api_url}/repos/#{config.repo_owner}/#{config.repo_name}/actions/runs/#{run_id}/cancel"

    headers = [
      {"Authorization", "Bearer #{config.token}"},
      {"Accept", "application/vnd.github.v3+json"}
    ]

    case Req.post(url, headers: headers) do
      {:ok, %Req.Response{status: 202}} ->
        {:ok, :cancelled}

      {:ok, %Req.Response{status: status}} ->
        {:error, "GitHub API error: #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp parse_github_status("queued", _), do: :queued
  defp parse_github_status("in_progress", _), do: :running
  defp parse_github_status("completed", "success"), do: :completed
  defp parse_github_status("completed", "failure"), do: :failed
  defp parse_github_status("completed", "cancelled"), do: :cancelled
  defp parse_github_status("completed", "timed_out"), do: :timeout
  defp parse_github_status(status, conclusion), do: {:unknown, status, conclusion}
end
