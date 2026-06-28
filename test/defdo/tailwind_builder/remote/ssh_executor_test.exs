defmodule Defdo.TailwindBuilder.Remote.SSHExecutorTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Remote.SSHExecutor

  describe "run/3 with injectable runner" do
    test "returns ok with stdout and exit_status 0" do
      runner = fn _host, _cmd, _opts ->
        {:ok, %{stdout: "builder-1\n", exit_status: 0}}
      end

      assert {:ok, result} = SSHExecutor.run("example.com", "hostname", runner: runner)
      assert result.stdout == "builder-1\n"
      assert result.exit_status == 0
    end

    test "returns ok with non-zero exit status (not an error)" do
      runner = fn _host, _cmd, _opts ->
        {:ok, %{stdout: "error output\n", exit_status: 1}}
      end

      assert {:ok, result} = SSHExecutor.run("example.com", "false", runner: runner)
      assert result.exit_status == 1
    end

    test "propagates runner error" do
      runner = fn _host, _cmd, _opts ->
        {:error, {:timeout_ms, 100}}
      end

      assert {:error, {:timeout_ms, 100}} =
               SSHExecutor.run("example.com", "sleep 1", runner: runner)
    end

    test "passes host and command to the runner" do
      parent = self()

      runner = fn host, cmd, _opts ->
        send(parent, {:called, host, cmd})
        {:ok, %{stdout: "", exit_status: 0}}
      end

      SSHExecutor.run("my-host.example.com", "echo hello", runner: runner)
      assert_received {:called, "my-host.example.com", "echo hello"}
    end
  end

  describe "redact_secrets/2" do
    test "replaces secret value with placeholder" do
      cmd = "R2_ACCESS_KEY_ID='supersecret' mix tailwind.release"

      redacted = SSHExecutor.redact_secrets(cmd, %{"supersecret" => "[REDACTED]"})
      assert redacted == "R2_ACCESS_KEY_ID='[REDACTED]' mix tailwind.release"
      refute String.contains?(redacted, "supersecret")
    end

    test "replaces multiple secrets" do
      cmd = "KEY='abc123' SECRET='xyz789' mix release"

      redacted =
        SSHExecutor.redact_secrets(cmd, %{"abc123" => "[REDACTED]", "xyz789" => "[REDACTED]"})

      refute String.contains?(redacted, "abc123")
      refute String.contains?(redacted, "xyz789")
    end

    test "leaves command unchanged when no secrets match" do
      cmd = "cd /workdir && mix tailwind.release"
      result = SSHExecutor.redact_secrets(cmd, %{"nonexistent" => "[REDACTED]"})
      assert result == cmd
    end

    test "handles empty secret map" do
      cmd = "mix tailwind.release"
      assert SSHExecutor.redact_secrets(cmd, %{}) == cmd
    end

    test "skips nil and empty-string values in secret map" do
      cmd = "mix tailwind.release"
      result = SSHExecutor.redact_secrets(cmd, %{"" => "[REDACTED]", nil => "[REDACTED]"})
      assert result == cmd
    end
  end

  describe "build_ssh_flags/2" do
    test "includes BatchMode=yes by default" do
      flags = SSHExecutor.build_ssh_flags("example.com")
      assert "-o" in flags
      assert "BatchMode=yes" in flags
    end

    test "includes host as last element before command" do
      flags = SSHExecutor.build_ssh_flags("example.com")
      assert List.last(flags) == "example.com"
    end

    test "includes identity flag when :identity is provided" do
      flags = SSHExecutor.build_ssh_flags("example.com", identity: "/home/user/.ssh/id_ed25519")
      assert "-i" in flags
      assert "/home/user/.ssh/id_ed25519" in flags
    end

    test "appends extra ssh_options" do
      flags = SSHExecutor.build_ssh_flags("example.com", ssh_options: ["-p", "2222"])
      assert "-p" in flags
      assert "2222" in flags
    end
  end
end
