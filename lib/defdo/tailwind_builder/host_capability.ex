defmodule Defdo.TailwindBuilder.HostCapability do
  @moduledoc """
  Host build capability detector.

  Probes a host (local or remote) for the tools and platform information needed
  to build a Tailwind v4 standalone binary. Returns a structured capability map
  with canonical `target_key`, `build_target`, and `artifact_name` resolved
  through `Defdo.TailwindBuilder.Core.Targets`.

  A missing tool is reported in `:missing_tools`, never as a crash.
  An unsupported platform sets `:build_capable` to `false` and populates
  `:target_key` with `nil`.

  ## Local detection

      capability = HostCapability.detect_local()
      # %{hostname: "mac-mini", target_key: "macos-arm64", build_capable: true, ...}

  ## Remote detection (via SSH)

      capability = HostCapability.detect_remote("builder.example.com", ssh_opts: [...])
      # %{hostname: "builder", target_key: "linux-x64", build_capable: true, ...}

  ## Injectable runner (for tests)

      runner = fn cmd -> {:ok, %{stdout: fake_output, exit_status: 0}} end
      capability = HostCapability.detect(runner: runner)
  """

  require Logger

  alias Defdo.TailwindBuilder.Core.Targets
  alias Defdo.TailwindBuilder.Remote.SSHExecutor

  @required_tools_v4 ~w(node pnpm rustc bun)

  @capability_probe_script """
  set +e
  echo "CAPABILITY_START"
  echo "hostname=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
  echo "os=$(uname -s 2>/dev/null || echo unknown)"
  echo "arch=$(uname -m 2>/dev/null || echo unknown)"
  if command -v elixir >/dev/null 2>&1; then
    echo "elixir_version=$(elixir --version 2>&1 | grep -i 'Elixir' | awk '{print $2}' | head -1)"
  else
    echo "elixir_version=missing"
  fi
  if command -v erl >/dev/null 2>&1; then
    echo "otp_release=$(erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().' 2>/dev/null | head -1 || echo missing)"
  else
    echo "otp_release=missing"
  fi
  if command -v node >/dev/null 2>&1; then
    echo "node_version=$(node --version 2>/dev/null | tr -d 'v')"
  else
    echo "node_version=missing"
  fi
  if command -v pnpm >/dev/null 2>&1; then
    echo "pnpm_version=$(pnpm --version 2>/dev/null)"
  else
    echo "pnpm_version=missing"
  fi
  if command -v rustc >/dev/null 2>&1; then
    echo "rust_version=$(rustc --version 2>/dev/null | awk '{print $2}')"
  else
    echo "rust_version=missing"
  fi
  if command -v bun >/dev/null 2>&1; then
    echo "bun_version=$(bun --version 2>/dev/null)"
  else
    echo "bun_version=missing"
  fi
  if command -v git >/dev/null 2>&1; then
    echo "git_sha=$(git rev-parse --short HEAD 2>/dev/null || echo none)"
  else
    echo "git_sha=none"
  fi
  if [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
    echo "cluster_env=kubernetes"
  elif [ -n "${NOMAD_TASK_NAME:-}" ]; then
    echo "cluster_env=nomad"
  else
    echo "cluster_env=none"
  fi
  if command -v docker >/dev/null 2>&1 && timeout 5 docker info >/dev/null 2>&1; then
    echo "container_engine=docker"
  elif command -v podman >/dev/null 2>&1 && timeout 5 podman info >/dev/null 2>&1; then
    echo "container_engine=podman"
  else
    echo "container_engine=none"
  fi
  if command -v mise >/dev/null 2>&1; then
    echo "setup_manager=mise"
    echo "setup_manager_path=$(command -v mise)"
  elif command -v asdf >/dev/null 2>&1; then
    echo "setup_manager=asdf"
    echo "setup_manager_path=$(command -v asdf)"
  else
    echo "setup_manager=none"
    echo "setup_manager_path=none"
  fi
  echo "CAPABILITY_END"
  """

  @type capability :: %{
          hostname: String.t(),
          os: String.t(),
          arch: String.t(),
          target_key: String.t() | nil,
          build_target: String.t() | nil,
          artifact_name: String.t() | nil,
          elixir_version: String.t() | nil,
          otp_release: String.t() | nil,
          node_version: String.t() | nil,
          rust_version: String.t() | nil,
          bun_version: String.t() | nil,
          pnpm_version: String.t() | nil,
          git_sha: String.t() | nil,
          build_capable: boolean(),
          missing_tools: [String.t()],
          container_engine: :docker | :podman | :none,
          setup_manager: :mise | :asdf | :none,
          setup_manager_path: String.t() | nil,
          cluster_env: :kubernetes | :nomad | :none,
          execution_strategy: :bare_metal | :container | :setup_then_build | :not_buildable
        }

  @doc """
  Detect the local host's build capability.
  """
  @spec detect_local(keyword()) :: capability()
  def detect_local(opts \\ []) do
    runner = fn cmd ->
      try do
        case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
          {output, _code} -> {:ok, %{stdout: output, exit_status: 0}}
        end
      rescue
        e -> {:error, {:sh_failed, Exception.message(e)}}
      end
    end

    detect(Keyword.put(opts, :runner, runner))
  end

  @doc """
  Detect a remote host's build capability over SSH.
  """
  @spec detect_remote(String.t(), keyword()) :: capability() | {:error, term()}
  def detect_remote(host, opts \\ []) do
    ssh_runner = Keyword.get(opts, :runner)

    runner = fn cmd ->
      ssh_opts = Keyword.drop(opts, [:runner])

      if ssh_runner do
        ssh_runner.(cmd)
      else
        SSHExecutor.run(host, cmd, ssh_opts)
      end
    end

    detect(Keyword.put(opts, :runner, runner))
  end

  @doc """
  Detect host capability using a caller-provided shell command runner.

  The `runner` must be a function `(command :: String.t() -> {:ok, %{stdout: binary, exit_status: integer}} | {:error, term})`.
  """
  @spec detect(keyword()) :: capability() | {:error, term()}
  def detect(opts \\ []) do
    runner = Keyword.fetch!(opts, :runner)

    case runner.(@capability_probe_script) do
      {:ok, %{stdout: output}} ->
        output |> parse_probe_output() |> enrich_capability()

      {:error, reason} ->
        {:error, {:probe_failed, reason}}
    end
  end

  @doc """
  Return `true` when a capability map indicates the host can build Tailwind v4.
  """
  @spec build_capable?(capability()) :: boolean()
  def build_capable?(%{build_capable: value}), do: value
  def build_capable?(_), do: false

  # Parse KEY=VALUE lines between CAPABILITY_START and CAPABILITY_END markers.
  defp parse_probe_output(output) when is_binary(output) do
    lines =
      output
      |> String.split("\n")
      |> Enum.map(&String.trim/1)

    in_block =
      Enum.reduce(lines, {false, %{}}, fn line, {active, acc} ->
        cond do
          line == "CAPABILITY_START" -> {true, acc}
          line == "CAPABILITY_END" -> {false, acc}
          active and String.contains?(line, "=") -> {true, put_kv(acc, line)}
          true -> {active, acc}
        end
      end)

    elem(in_block, 1)
  end

  defp put_kv(acc, line) do
    case String.split(line, "=", parts: 2) do
      [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
      _ -> acc
    end
  end

  defp enrich_capability(raw) when is_map(raw) do
    os = normalize_os(Map.get(raw, "os", "unknown"))
    arch = normalize_arch(Map.get(raw, "arch", "unknown"))
    raw_target = raw_target_string(os, arch)

    {target_key, build_target, artifact_name} = resolve_target(raw_target)

    node_version = nil_if_missing(Map.get(raw, "node_version"))
    pnpm_version = nil_if_missing(Map.get(raw, "pnpm_version"))
    rust_version = nil_if_missing(Map.get(raw, "rust_version"))
    bun_version = nil_if_missing(Map.get(raw, "bun_version"))
    elixir_version = nil_if_missing(Map.get(raw, "elixir_version"))
    otp_release = nil_if_missing(Map.get(raw, "otp_release"))
    git_sha = nil_if_missing_or_none(Map.get(raw, "git_sha"))

    tool_presence = %{
      "node" => node_version,
      "pnpm" => pnpm_version,
      "rustc" => rust_version,
      "bun" => bun_version
    }

    missing_tools =
      @required_tools_v4
      |> Enum.filter(fn tool -> is_nil(tool_presence[tool]) end)

    build_capable = target_key != nil and missing_tools == []

    container_engine = parse_container_engine(Map.get(raw, "container_engine"))
    setup_manager = parse_setup_manager(Map.get(raw, "setup_manager"))
    setup_manager_path = nil_if_missing_or_none(Map.get(raw, "setup_manager_path"))
    cluster_env = parse_cluster_env(Map.get(raw, "cluster_env"))

    execution_strategy =
      resolve_execution_strategy(%{
        build_capable: build_capable,
        container_engine: container_engine,
        setup_manager: setup_manager,
        cluster_env: cluster_env
      })

    %{
      hostname: Map.get(raw, "hostname", "unknown"),
      os: os,
      arch: arch,
      target_key: target_key,
      build_target: build_target,
      artifact_name: artifact_name,
      elixir_version: elixir_version,
      otp_release: otp_release,
      node_version: node_version,
      rust_version: rust_version,
      bun_version: bun_version,
      pnpm_version: pnpm_version,
      git_sha: git_sha,
      build_capable: build_capable,
      missing_tools: missing_tools,
      container_engine: container_engine,
      setup_manager: setup_manager,
      setup_manager_path: setup_manager_path,
      cluster_env: cluster_env,
      execution_strategy: execution_strategy
    }
  end

  defp parse_container_engine("docker"), do: :docker
  defp parse_container_engine("podman"), do: :podman
  defp parse_container_engine(_), do: :none

  defp parse_setup_manager("mise"), do: :mise
  defp parse_setup_manager("asdf"), do: :asdf
  defp parse_setup_manager(_), do: :none

  defp parse_cluster_env("kubernetes"), do: :kubernetes
  defp parse_cluster_env("nomad"), do: :nomad
  defp parse_cluster_env(_), do: :none

  # Strategy priority:
  # 1. Cluster env → bare_metal (the container IS the runtime; tools must be provisioned)
  # 2. All tools present → bare_metal
  # 3. Container engine usable → container (reproducible, no host setup)
  # 4. Setup manager present → setup_then_build (install missing tools first)
  # 5. Nothing → not_buildable
  defp resolve_execution_strategy(%{cluster_env: env}) when env in [:kubernetes, :nomad] do
    :bare_metal
  end

  defp resolve_execution_strategy(%{build_capable: true}) do
    :bare_metal
  end

  defp resolve_execution_strategy(%{container_engine: engine})
       when engine in [:docker, :podman] do
    :container
  end

  defp resolve_execution_strategy(%{setup_manager: manager}) when manager in [:mise, :asdf] do
    :setup_then_build
  end

  defp resolve_execution_strategy(_) do
    :not_buildable
  end

  defp normalize_os("Darwin"), do: "macos"
  defp normalize_os("darwin"), do: "macos"
  defp normalize_os("Linux"), do: "linux"
  defp normalize_os("linux"), do: "linux"
  defp normalize_os("Windows_NT"), do: "windows"
  defp normalize_os("MINGW" <> _), do: "windows"
  defp normalize_os("FreeBSD"), do: "freebsd"
  defp normalize_os(other), do: String.downcase(other)

  defp normalize_arch("x86_64"), do: "x86_64"
  defp normalize_arch("amd64"), do: "x86_64"
  defp normalize_arch("aarch64"), do: "aarch64"
  defp normalize_arch("arm64"), do: "aarch64"
  defp normalize_arch("armv7l"), do: "armv7"
  defp normalize_arch("armv7"), do: "armv7"
  defp normalize_arch(other), do: String.downcase(other)

  defp raw_target_string("macos", "aarch64"), do: "macos-arm64"
  defp raw_target_string("macos", "x86_64"), do: "macos-x64"
  defp raw_target_string("linux", "x86_64"), do: "linux-x64"
  defp raw_target_string("linux", "aarch64"), do: "linux-arm64"
  defp raw_target_string("linux", "armv7"), do: "linux-arm"
  defp raw_target_string("windows", "x86_64"), do: "windows-x64"
  defp raw_target_string("windows", "aarch64"), do: "windows-arm64"
  defp raw_target_string("freebsd", "x86_64"), do: "freebsd-x64"
  defp raw_target_string(_os, _arch), do: nil

  defp resolve_target(nil), do: {nil, nil, nil}

  defp resolve_target(raw) do
    case Targets.normalize(raw) do
      {:ok, %{target_key: tk, build_target: bt, artifact_name: an}} -> {tk, bt, an}
      {:error, :unknown_target} -> {nil, nil, nil}
    end
  end

  defp nil_if_missing(nil), do: nil
  defp nil_if_missing(""), do: nil
  defp nil_if_missing("missing"), do: nil

  defp nil_if_missing(v) when is_binary(v),
    do: if(String.trim(v) == "", do: nil, else: String.trim(v))

  defp nil_if_missing_or_none(nil), do: nil
  defp nil_if_missing_or_none("none"), do: nil
  defp nil_if_missing_or_none(v), do: nil_if_missing(v)
end
