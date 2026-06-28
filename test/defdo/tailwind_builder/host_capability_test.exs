defmodule Defdo.TailwindBuilder.HostCapabilityTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.HostCapability

  # Simulates a fully capable Linux x64 host.
  defp linux_x64_runner(_cmd) do
    output = """
    CAPABILITY_START
    hostname=builder-1
    os=Linux
    arch=x86_64
    elixir_version=1.17.0
    otp_release=27
    node_version=22.0.0
    pnpm_version=9.0.0
    rust_version=1.78.0
    bun_version=1.3.0
    git_sha=abcdef0
    cluster_env=none
    container_engine=none
    setup_manager=none
    setup_manager_path=none
    CAPABILITY_END
    """

    {:ok, %{stdout: output, exit_status: 0}}
  end

  # Simulates a macOS arm64 host missing bun and pnpm.
  defp macos_arm64_missing_tools_runner(_cmd) do
    output = """
    CAPABILITY_START
    hostname=mac-mini
    os=Darwin
    arch=aarch64
    elixir_version=1.17.0
    otp_release=26
    node_version=20.0.0
    pnpm_version=missing
    rust_version=1.78.0
    bun_version=missing
    git_sha=none
    CAPABILITY_END
    """

    {:ok, %{stdout: output, exit_status: 0}}
  end

  # Simulates an unknown arch host.
  defp unknown_arch_runner(_cmd) do
    output = """
    CAPABILITY_START
    hostname=strange-box
    os=unknown_os
    arch=riscv64
    elixir_version=missing
    otp_release=missing
    node_version=missing
    pnpm_version=missing
    rust_version=missing
    bun_version=missing
    git_sha=none
    CAPABILITY_END
    """

    {:ok, %{stdout: output, exit_status: 0}}
  end

  describe "detect/1 with injectable runner" do
    test "returns full capability map for a capable linux-x64 host" do
      cap = HostCapability.detect(runner: &linux_x64_runner/1)

      assert cap.hostname == "builder-1"
      assert cap.os == "linux"
      assert cap.arch == "x86_64"
      assert cap.target_key == "linux-x64"
      assert cap.build_target == "x86_64-unknown-linux-gnu"
      assert cap.artifact_name == "tailwindcss-linux-x64"
      assert cap.build_capable == true
      assert cap.missing_tools == []
      assert cap.elixir_version == "1.17.0"
      assert cap.otp_release == "27"
      assert cap.node_version == "22.0.0"
      assert cap.pnpm_version == "9.0.0"
      assert cap.rust_version == "1.78.0"
      assert cap.bun_version == "1.3.0"
      assert cap.git_sha == "abcdef0"
    end

    test "reports missing tools without crashing" do
      cap = HostCapability.detect(runner: &macos_arm64_missing_tools_runner/1)

      assert cap.target_key == "macos-arm64"
      assert cap.build_capable == false
      assert "pnpm" in cap.missing_tools
      assert "bun" in cap.missing_tools
      assert cap.node_version == "20.0.0"
      assert cap.pnpm_version == nil
      assert cap.bun_version == nil
      assert cap.git_sha == nil
    end

    test "returns not build_capable for unknown target" do
      cap = HostCapability.detect(runner: &unknown_arch_runner/1)

      assert cap.target_key == nil
      assert cap.build_capable == false
      assert cap.build_target == nil
      assert cap.artifact_name == nil
    end

    test "propagates runner error" do
      error_runner = fn _cmd -> {:error, {:ssh_failed, "connection refused"}} end
      assert {:error, {:probe_failed, _}} = HostCapability.detect(runner: error_runner)
    end

    test "handles probe output missing CAPABILITY_START/END markers" do
      partial_runner = fn _cmd ->
        {:ok, %{stdout: "some noise\nhostname=foo\nos=Linux", exit_status: 0}}
      end

      cap = HostCapability.detect(runner: partial_runner)
      assert cap.target_key == nil
      assert cap.build_capable == false
    end
  end

  describe "target_key resolution" do
    test "macos arm64 resolves to macos-arm64" do
      runner = fn _cmd ->
        output = """
        CAPABILITY_START
        hostname=mac
        os=Darwin
        arch=arm64
        elixir_version=1.17.0
        otp_release=26
        node_version=20.0.0
        pnpm_version=9.0.0
        rust_version=1.78.0
        bun_version=1.3.0
        git_sha=none
        CAPABILITY_END
        """

        {:ok, %{stdout: output, exit_status: 0}}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.target_key == "macos-arm64"
      assert cap.build_target == "aarch64-apple-darwin"
    end

    test "linux aarch64 resolves to linux-arm64" do
      runner = fn _cmd ->
        output = """
        CAPABILITY_START
        hostname=rpi
        os=Linux
        arch=aarch64
        elixir_version=1.17.0
        otp_release=26
        node_version=20.0.0
        pnpm_version=9.0.0
        rust_version=1.78.0
        bun_version=1.3.0
        git_sha=none
        CAPABILITY_END
        """

        {:ok, %{stdout: output, exit_status: 0}}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.target_key == "linux-arm64"
      assert cap.build_target == "aarch64-unknown-linux-gnu"
    end

    test "linux armv7l resolves to linux-arm" do
      runner = fn _cmd ->
        output = """
        CAPABILITY_START
        hostname=rpi2
        os=Linux
        arch=armv7l
        elixir_version=missing
        otp_release=missing
        node_version=20.0.0
        pnpm_version=9.0.0
        rust_version=1.78.0
        bun_version=1.3.0
        git_sha=none
        CAPABILITY_END
        """

        {:ok, %{stdout: output, exit_status: 0}}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.target_key == "linux-arm"
      assert cap.build_target == "armv7-unknown-linux-gnueabihf"
      assert cap.artifact_name == "tailwindcss-linux-arm"
    end
  end

  describe "build_capable?/1" do
    test "returns true for a capable host" do
      cap = HostCapability.detect(runner: &linux_x64_runner/1)
      assert HostCapability.build_capable?(cap)
    end

    test "returns false for a host missing tools" do
      cap = HostCapability.detect(runner: &macos_arm64_missing_tools_runner/1)
      refute HostCapability.build_capable?(cap)
    end

    test "returns false for a map without build_capable key" do
      refute HostCapability.build_capable?(%{})
    end
  end

  describe "execution_strategy resolution" do
    test "bare_metal when all tools present" do
      runner = fn _cmd ->
        {:ok,
         %{
           stdout: """
           CAPABILITY_START
           hostname=builder
           os=Linux
           arch=x86_64
           elixir_version=1.17.0
           otp_release=27
           node_version=22.0.0
           pnpm_version=9.0.0
           rust_version=1.78.0
           bun_version=1.3.0
           git_sha=abc
           cluster_env=none
           container_engine=none
           setup_manager=none
           setup_manager_path=none
           CAPABILITY_END
           """,
           exit_status: 0
         }}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.execution_strategy == :bare_metal
      assert cap.container_engine == :none
      assert cap.setup_manager == :none
      assert cap.cluster_env == :none
    end

    test "container when docker usable and tools missing" do
      runner = fn _cmd ->
        {:ok,
         %{
           stdout: """
           CAPABILITY_START
           hostname=ci-host
           os=Linux
           arch=x86_64
           elixir_version=missing
           otp_release=missing
           node_version=missing
           pnpm_version=missing
           rust_version=missing
           bun_version=missing
           git_sha=none
           cluster_env=none
           container_engine=docker
           setup_manager=none
           setup_manager_path=none
           CAPABILITY_END
           """,
           exit_status: 0
         }}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.execution_strategy == :container
      assert cap.container_engine == :docker
      assert cap.build_capable == false
    end

    test "container when podman usable and tools missing" do
      runner = fn _cmd ->
        {:ok,
         %{
           stdout: """
           CAPABILITY_START
           hostname=ci-host
           os=Linux
           arch=x86_64
           elixir_version=missing
           otp_release=missing
           node_version=missing
           pnpm_version=missing
           rust_version=missing
           bun_version=missing
           git_sha=none
           cluster_env=none
           container_engine=podman
           setup_manager=none
           setup_manager_path=none
           CAPABILITY_END
           """,
           exit_status: 0
         }}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.execution_strategy == :container
      assert cap.container_engine == :podman
    end

    test "setup_then_build when mise present and no container engine" do
      runner = fn _cmd ->
        {:ok,
         %{
           stdout: """
           CAPABILITY_START
           hostname=bare-host
           os=Linux
           arch=x86_64
           elixir_version=missing
           otp_release=missing
           node_version=missing
           pnpm_version=missing
           rust_version=missing
           bun_version=missing
           git_sha=none
           cluster_env=none
           container_engine=none
           setup_manager=mise
           setup_manager_path=/home/ubuntu/.local/bin/mise
           CAPABILITY_END
           """,
           exit_status: 0
         }}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.execution_strategy == :setup_then_build
      assert cap.setup_manager == :mise
      assert cap.setup_manager_path == "/home/ubuntu/.local/bin/mise"
    end

    test "setup_then_build when asdf present and no container engine" do
      runner = fn _cmd ->
        {:ok,
         %{
           stdout: """
           CAPABILITY_START
           hostname=bare-host
           os=Linux
           arch=x86_64
           elixir_version=missing
           otp_release=missing
           node_version=missing
           pnpm_version=missing
           rust_version=missing
           bun_version=missing
           git_sha=none
           cluster_env=none
           container_engine=none
           setup_manager=asdf
           setup_manager_path=/usr/local/bin/asdf
           CAPABILITY_END
           """,
           exit_status: 0
         }}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.execution_strategy == :setup_then_build
      assert cap.setup_manager == :asdf
    end

    test "not_buildable when no tools, no container, no setup manager" do
      runner = fn _cmd ->
        {:ok,
         %{
           stdout: """
           CAPABILITY_START
           hostname=empty-host
           os=Linux
           arch=x86_64
           elixir_version=missing
           otp_release=missing
           node_version=missing
           pnpm_version=missing
           rust_version=missing
           bun_version=missing
           git_sha=none
           cluster_env=none
           container_engine=none
           setup_manager=none
           setup_manager_path=none
           CAPABILITY_END
           """,
           exit_status: 0
         }}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.execution_strategy == :not_buildable
    end

    test "bare_metal in kubernetes cluster regardless of tool presence" do
      runner = fn _cmd ->
        {:ok,
         %{
           stdout: """
           CAPABILITY_START
           hostname=pod-abc123
           os=Linux
           arch=x86_64
           elixir_version=missing
           otp_release=missing
           node_version=missing
           pnpm_version=missing
           rust_version=missing
           bun_version=missing
           git_sha=none
           cluster_env=kubernetes
           container_engine=none
           setup_manager=none
           setup_manager_path=none
           CAPABILITY_END
           """,
           exit_status: 0
         }}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.execution_strategy == :bare_metal
      assert cap.cluster_env == :kubernetes
    end

    test "bare_metal in nomad cluster" do
      runner = fn _cmd ->
        {:ok,
         %{
           stdout: """
           CAPABILITY_START
           hostname=nomad-1
           os=Linux
           arch=x86_64
           elixir_version=missing
           otp_release=missing
           node_version=missing
           pnpm_version=missing
           rust_version=missing
           bun_version=missing
           git_sha=none
           cluster_env=nomad
           container_engine=none
           setup_manager=none
           setup_manager_path=none
           CAPABILITY_END
           """,
           exit_status: 0
         }}
      end

      cap = HostCapability.detect(runner: runner)
      assert cap.execution_strategy == :bare_metal
      assert cap.cluster_env == :nomad
    end
  end

  describe "detect_local/0" do
    @tag :local_probe
    test "returns a capability map for the current host" do
      cap = HostCapability.detect_local()
      assert is_binary(cap.hostname)
      assert is_binary(cap.os)
      assert is_binary(cap.arch)
      assert is_boolean(cap.build_capable)
      assert is_list(cap.missing_tools)

      assert cap.execution_strategy in [
               :bare_metal,
               :container,
               :setup_then_build,
               :not_buildable
             ]

      assert cap.cluster_env in [:kubernetes, :nomad, :none]
      assert cap.container_engine in [:docker, :podman, :none]
      assert cap.setup_manager in [:mise, :asdf, :none]
    end
  end
end
