defmodule Defdo.TailwindBuilder.NodeManager do
  @moduledoc """
  Management system for distributed compilation nodes.

  This module handles:
  - Node registration and discovery
  - Health monitoring and heartbeats
  - Load balancing and job distribution
  - Node lifecycle management

  ## Architecture

  The NodeManager runs on the Build Coordinator and manages a pool of
  compilation nodes across different architectures and platforms.

  ## Usage

      # Start the node manager
      {:ok, pid} = NodeManager.start_link([])

      # Register a new node
      NodeManager.register_node(%{
        node_id: "node-linux-x64-001",
        architecture: "linux-x64",
        endpoint: "https://build-node-1.example.com",
        capabilities: ["tailwind-v3", "tailwind-v4"],
        max_concurrent: 2
      })

      # Find best node for a build
      {:ok, node} = NodeManager.find_available_node("linux-x64")

      # Submit build to node
      {:ok, job_id} = NodeManager.submit_build(node, build_request)
  """

  use GenServer
  require Logger

  # Node states (for future reference)
  # @node_states [:available, :busy, :maintenance, :offline]

  # Default configuration
  @default_heartbeat_timeout 60_000  # 1 minute
  @default_health_check_interval 30_000  # 30 seconds

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new compilation node
  """
  def register_node(node_info) do
    GenServer.call(__MODULE__, {:register_node, node_info})
  end

  @doc """
  Update node heartbeat
  """
  def node_heartbeat(node_id, status_info) do
    GenServer.cast(__MODULE__, {:node_heartbeat, node_id, status_info})
  end

  @doc """
  Find available node for specific architecture
  """
  def find_available_node(architecture, requirements \\ %{}) do
    GenServer.call(__MODULE__, {:find_available_node, architecture, requirements})
  end

  @doc """
  Submit build job to specific node
  """
  def submit_build(node_id, build_request) do
    GenServer.call(__MODULE__, {:submit_build, node_id, build_request})
  end

  @doc """
  Get all registered nodes
  """
  def list_nodes do
    GenServer.call(__MODULE__, :list_nodes)
  end

  @doc """
  Get node statistics
  """
  def node_stats(node_id) do
    GenServer.call(__MODULE__, {:node_stats, node_id})
  end

  @doc """
  Remove/deregister a node
  """
  def deregister_node(node_id) do
    GenServer.call(__MODULE__, {:deregister_node, node_id})
  end

  ## GenServer Callbacks

  def init(opts) do
    # Start periodic health checks
    schedule_health_check()

    state = %{
      nodes: %{},
      job_queue: :queue.new(),
      active_jobs: %{},
      node_stats: %{},
      config: %{
        heartbeat_timeout: Keyword.get(opts, :heartbeat_timeout, @default_heartbeat_timeout),
        health_check_interval: Keyword.get(opts, :health_check_interval, @default_health_check_interval)
      }
    }

    Logger.info("NodeManager started")
    {:ok, state}
  end

  def handle_call({:register_node, node_info}, _from, state) do
    case validate_node_info(node_info) do
      {:ok, validated_node} ->
        node_id = validated_node.node_id

        node = %{
          node_id: node_id,
          architecture: validated_node.architecture,
          endpoint: validated_node.endpoint,
          capabilities: validated_node.capabilities,
          max_concurrent: validated_node.max_concurrent,
          status: :available,
          current_jobs: 0,
          registered_at: DateTime.utc_now(),
          last_heartbeat: DateTime.utc_now(),
          total_builds: 0,
          success_rate: 1.0,
          average_build_time: nil
        }

        updated_nodes = Map.put(state.nodes, node_id, node)
        updated_stats = Map.put(state.node_stats, node_id, init_node_stats())

        Logger.info("Node registered: #{node_id} (#{node.architecture})")

        {:reply, {:ok, node_id}, %{state |
          nodes: updated_nodes,
          node_stats: updated_stats
        }}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:find_available_node, architecture, requirements}, _from, state) do
    case find_best_node(state.nodes, architecture, requirements) do
      {:ok, node} ->
        {:reply, {:ok, node}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:submit_build, node_id, build_request}, _from, state) do
    case Map.get(state.nodes, node_id) do
      nil ->
        {:reply, {:error, :node_not_found}, state}

      node ->
        case can_accept_job?(node) do
          true ->
            case send_build_to_node(node, build_request) do
              {:ok, job_id} ->
                # Update node status
                updated_node = %{node | current_jobs: node.current_jobs + 1}
                updated_nodes = Map.put(state.nodes, node_id, updated_node)

                # Track active job
                job_info = %{
                  job_id: job_id,
                  node_id: node_id,
                  build_request: build_request,
                  started_at: DateTime.utc_now()
                }
                updated_jobs = Map.put(state.active_jobs, job_id, job_info)

                {:reply, {:ok, job_id}, %{state |
                  nodes: updated_nodes,
                  active_jobs: updated_jobs
                }}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end

          false ->
            {:reply, {:error, :node_busy}, state}
        end
    end
  end

  def handle_call(:list_nodes, _from, state) do
    nodes_list = Map.values(state.nodes)
    {:reply, {:ok, nodes_list}, state}
  end

  def handle_call({:node_stats, node_id}, _from, state) do
    case Map.get(state.node_stats, node_id) do
      nil -> {:reply, {:error, :node_not_found}, state}
      stats -> {:reply, {:ok, stats}, state}
    end
  end

  def handle_call({:deregister_node, node_id}, _from, state) do
    case Map.get(state.nodes, node_id) do
      nil ->
        {:reply, {:error, :node_not_found}, state}

      _node ->
        updated_nodes = Map.delete(state.nodes, node_id)
        updated_stats = Map.delete(state.node_stats, node_id)

        # Cancel any active jobs on this node
        updated_jobs = state.active_jobs
        |> Enum.reject(fn {_job_id, job_info} -> job_info.node_id == node_id end)
        |> Enum.into(%{})

        Logger.info("Node deregistered: #{node_id}")

        {:reply, :ok, %{state |
          nodes: updated_nodes,
          node_stats: updated_stats,
          active_jobs: updated_jobs
        }}
    end
  end

  def handle_cast({:node_heartbeat, node_id, status_info}, state) do
    case Map.get(state.nodes, node_id) do
      nil ->
        Logger.warning("Received heartbeat from unknown node: #{node_id}")
        {:noreply, state}

      node ->
        updated_node = %{node |
          last_heartbeat: DateTime.utc_now(),
          status: Map.get(status_info, "status", node.status),
          current_jobs: Map.get(status_info, "current_jobs", node.current_jobs)
        }

        updated_nodes = Map.put(state.nodes, node_id, updated_node)

        # Update node stats if provided
        updated_stats = case Map.get(status_info, "system_info") do
          nil -> state.node_stats
          system_info -> update_node_system_stats(state.node_stats, node_id, system_info)
        end

        {:noreply, %{state | nodes: updated_nodes, node_stats: updated_stats}}
    end
  end

  def handle_info(:health_check, state) do
    # Check for offline nodes
    now = DateTime.utc_now()
    timeout_ms = state.config.heartbeat_timeout

    {offline_nodes, active_nodes} = state.nodes
    |> Enum.split_with(fn {_node_id, node} ->
      DateTime.diff(now, node.last_heartbeat, :millisecond) > timeout_ms
    end)

    # Mark offline nodes
    updated_nodes = active_nodes
    |> Enum.into(%{})
    |> Map.merge(
      offline_nodes
      |> Enum.map(fn {node_id, node} -> {node_id, %{node | status: :offline}} end)
      |> Enum.into(%{})
    )

    # Log offline nodes
    Enum.each(offline_nodes, fn {node_id, _node} ->
      Logger.warning("Node marked as offline: #{node_id}")
    end)

    # Schedule next health check
    schedule_health_check(state.config.health_check_interval)

    {:noreply, %{state | nodes: updated_nodes}}
  end

  def handle_info({:job_completed, job_id, result}, state) do
    case Map.get(state.active_jobs, job_id) do
      nil ->
        Logger.warning("Received completion for unknown job: #{job_id}")
        {:noreply, state}

      job_info ->
        node_id = job_info.node_id
        duration = DateTime.diff(DateTime.utc_now(), job_info.started_at, :millisecond)

        # Update node stats
        updated_nodes = update_node_completion_stats(state.nodes, node_id, result, duration)
        updated_jobs = Map.delete(state.active_jobs, job_id)

        Logger.info("Job completed: #{job_id} on #{node_id} (#{duration}ms)")

        {:noreply, %{state | nodes: updated_nodes, active_jobs: updated_jobs}}
    end
  end

  ## Private Functions

  defp validate_node_info(node_info) do
    required_fields = [:node_id, :architecture, :endpoint, :capabilities]

    case check_required_fields(node_info, required_fields) do
      :ok ->
        validated = %{
          node_id: node_info.node_id,
          architecture: node_info.architecture,
          endpoint: node_info.endpoint,
          capabilities: node_info.capabilities,
          max_concurrent: Map.get(node_info, :max_concurrent, 1)
        }
        {:ok, validated}

      {:error, missing_fields} ->
        {:error, {:missing_fields, missing_fields}}
    end
  end

  defp check_required_fields(map, required_fields) do
    missing = Enum.filter(required_fields, fn field ->
      not Map.has_key?(map, field) or is_nil(Map.get(map, field))
    end)

    case missing do
      [] -> :ok
      fields -> {:error, fields}
    end
  end

  defp find_best_node(nodes, architecture, requirements) do
    candidates = nodes
    |> Map.values()
    |> Enum.filter(fn node ->
      node.architecture == architecture and
      node.status == :available and
      can_accept_job?(node) and
      meets_requirements?(node, requirements)
    end)

    case candidates do
      [] ->
        {:error, :no_available_nodes}

      nodes_list ->
        # Score nodes based on load, performance, etc.
        best_node = nodes_list
        |> Enum.max_by(&score_node/1)

        {:ok, best_node}
    end
  end

  defp can_accept_job?(node) do
    node.current_jobs < node.max_concurrent and node.status == :available
  end

  defp meets_requirements?(node, requirements) do
    # Check if node meets specific requirements (version support, etc.)
    required_capabilities = Map.get(requirements, :capabilities, [])

    Enum.all?(required_capabilities, fn capability ->
      capability in node.capabilities
    end)
  end

  defp score_node(node) do
    # Simple scoring based on load and success rate
    load_factor = 1.0 - (node.current_jobs / node.max_concurrent)
    success_factor = node.success_rate

    load_factor * 0.6 + success_factor * 0.4
  end

  defp send_build_to_node(node, build_request) do
    # Send HTTP request to node's build endpoint
    url = "#{node.endpoint}/api/v1/build"
    headers = [{"content-type", "application/json"}]

    case Req.post(url, json: build_request, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"job_id" => job_id}}} ->
        {:ok, job_id}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp init_node_stats do
    %{
      total_builds: 0,
      successful_builds: 0,
      failed_builds: 0,
      average_build_time: 0,
      last_build_time: nil,
      system_load: 0.0,
      memory_usage: 0.0,
      disk_space: nil
    }
  end

  defp update_node_completion_stats(nodes, node_id, result, duration) do
    case Map.get(nodes, node_id) do
      nil -> nodes

      node ->
        updated_node = case result do
          :success ->
            new_total = node.total_builds + 1
            new_avg_time = case node.average_build_time do
              nil -> duration
              avg -> (avg * node.total_builds + duration) / new_total
            end

            %{node |
              total_builds: new_total,
              average_build_time: new_avg_time,
              success_rate: calculate_success_rate(new_total, new_total - node.total_builds + 1),
              current_jobs: max(0, node.current_jobs - 1)
            }

          :failure ->
            new_total = node.total_builds + 1

            %{node |
              total_builds: new_total,
              success_rate: calculate_success_rate(new_total, new_total - node.total_builds),
              current_jobs: max(0, node.current_jobs - 1)
            }
        end

        Map.put(nodes, node_id, updated_node)
    end
  end

  defp calculate_success_rate(total_builds, successful_builds) do
    if total_builds > 0 do
      successful_builds / total_builds
    else
      1.0
    end
  end

  defp update_node_system_stats(stats_map, node_id, system_info) do
    case Map.get(stats_map, node_id) do
      nil -> stats_map

      stats ->
        updated_stats = %{stats |
          system_load: Map.get(system_info, "load", stats.system_load),
          memory_usage: Map.get(system_info, "memory", stats.memory_usage),
          disk_space: Map.get(system_info, "disk", stats.disk_space)
        }

        Map.put(stats_map, node_id, updated_stats)
    end
  end

  defp schedule_health_check(interval \\ @default_health_check_interval) do
    Process.send_after(self(), :health_check, interval)
  end
end