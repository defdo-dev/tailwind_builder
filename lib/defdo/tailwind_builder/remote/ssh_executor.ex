defmodule Defdo.TailwindBuilder.Remote.SSHExecutor do
  @moduledoc """
  Thin SSH shell command executor for remote release orchestration.

  All public functions accept a `:runner` option that overrides the default
  `System.cmd("ssh", ...)` call. Inject a test double to avoid real SSH in
  the automated test suite.

  ## Secrets

  `redact_secrets/2` produces a printable copy of any command string with
  secret values replaced by `[REDACTED]`. Always log the redacted form, never
  the raw command that embeds credentials.

  ## Usage

      {:ok, result} = SSHExecutor.run("builder.example.com", "hostname", [])
      # result.stdout, result.exit_status

      printable = SSHExecutor.redact_secrets(cmd, %{"supersecret" => "[REDACTED]"})
  """

  require Logger

  @default_connect_timeout 30
  @default_timeout_ms 600_000

  @doc """
  Run `command` on `host` over SSH.

  Returns `{:ok, %{stdout: binary, exit_status: integer}}` on any completed
  execution (even non-zero exit), or `{:error, reason}` when the local `ssh`
  process cannot be launched.

  Options:
  - `:runner` — `(host, command, opts -> {:ok, map} | {:error, term})`. Replaces the default SSH call; inject in tests.
  - `:identity` — path to SSH private key (`-i path`).
  - `:ssh_options` — extra list of raw SSH flags (e.g. `["-p", "2222"]`).
  - `:timeout` — milliseconds before the Task is cancelled (default: `#{@default_timeout_ms}`).
  """
  @spec run(String.t(), String.t(), keyword()) ::
          {:ok, %{stdout: String.t(), exit_status: integer()}} | {:error, term()}
  def run(host, command, opts \\ []) do
    runner = Keyword.get(opts, :runner, &default_runner/3)
    runner.(host, command, opts)
  end

  @doc """
  Replace every occurrence of a secret value in `command` with its redacted form.

  `secret_map` is `%{value => replacement}`, e.g.
  `%{"s3cr3t" => "[REDACTED]"}`.

  Returns the sanitized string safe to log.
  """
  @spec redact_secrets(String.t(), %{String.t() => String.t()}) :: String.t()
  def redact_secrets(command, secret_map) when is_binary(command) and is_map(secret_map) do
    Enum.reduce(secret_map, command, fn {value, placeholder}, cmd ->
      if is_binary(value) and byte_size(value) > 0 do
        String.replace(cmd, value, placeholder)
      else
        cmd
      end
    end)
  end

  @doc """
  Build an SSH argv list (everything after `ssh`) from `host` and `opts`.

  Useful for inspection and logging. Does not include the actual command.
  """
  @spec build_ssh_flags(String.t(), keyword()) :: [String.t()]
  def build_ssh_flags(host, opts \\ []) do
    base = [
      "-o",
      "BatchMode=yes",
      "-o",
      "StrictHostKeyChecking=no",
      "-o",
      "ConnectTimeout=#{@default_connect_timeout}"
    ]

    identity_flags =
      case Keyword.get(opts, :identity) do
        nil -> []
        path -> ["-i", path]
      end

    extra = Keyword.get(opts, :ssh_options, [])
    base ++ identity_flags ++ extra ++ [host]
  end

  defp default_runner(host, command, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    ssh_flags = build_ssh_flags(host, opts)
    args = ssh_flags ++ [command]

    Logger.debug("SSH #{host}: running command (#{String.length(command)} chars)")

    task =
      Task.async(fn ->
        System.cmd("ssh", args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, exit_code}} ->
        {:ok, %{stdout: output, exit_status: exit_code}}

      nil ->
        {:error, {:timeout_ms, timeout}}
    end
  rescue
    e -> {:error, {:ssh_launch_failed, Exception.message(e)}}
  end
end
