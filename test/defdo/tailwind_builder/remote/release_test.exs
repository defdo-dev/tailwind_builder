defmodule Defdo.TailwindBuilder.Remote.ReleaseTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Remote.Release, as: RemoteRelease

  @linux_x64_probe_output """
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
  CAPABILITY_END
  """

  @not_buildable_probe_output """
  CAPABILITY_START
  hostname=partial-host
  os=Linux
  arch=x86_64
  elixir_version=1.17.0
  otp_release=27
  node_version=missing
  pnpm_version=missing
  rust_version=missing
  bun_version=missing
  git_sha=none
  CAPABILITY_END
  """

  defp capable_cap_runner(output) do
    fn _cmd -> {:ok, %{stdout: output, exit_status: 0}} end
  end

  defp tmp_report_path do
    dir = System.tmp_dir!()
    Path.join(dir, "test_report_#{System.unique_integer([:positive])}.json")
  end

  defp base_opts(extra \\ []) do
    Keyword.merge(
      [
        host: "builder.example.com",
        workdir: "/home/build/tailwind_builder",
        version: "4.2.2",
        release_channel: "v4.2.2-rc1",
        plugin: "daisyui_v5",
        bucket: "defdo",
        prefix: "tailwind_cli_daisyui",
        storage_base_url: "https://storage.defdo.de",
        config_provider: "testing",
        overwrite_policy: "fail",
        smoke_test: false,
        verify_upload: false,
        verify_smoke_test: false,
        report_path: tmp_report_path(),
        r2_access_key_id: "test-key",
        r2_secret_access_key: "test-secret",
        r2_host: "example.r2.cloudflarestorage.com",
        r2_region: "auto"
      ],
      extra
    )
  end

  describe "run/1 with injectable runners" do
    test "writes a published report on successful SSH execution" do
      release_runner = fn _host, _cmd, _opts ->
        {:ok, %{stdout: "Release completed successfully\n", exit_status: 0}}
      end

      # No manifest fetch possible in test; artifact will be nil
      opts =
        base_opts(
          cap_runner: capable_cap_runner(@linux_x64_probe_output),
          ssh_runner: release_runner
        )

      assert {:ok, report} = RemoteRelease.run(opts)
      assert report["status"] == "published"
      assert report["schema_version"] == 1
      assert report["release_channel"] == "v4.2.2-rc1"
      assert get_in(report, ["capability", "target_key"]) == "linux-x64"
      assert get_in(report, ["capability", "build_capable"]) == true
      assert get_in(report, ["remote", "host"]) == "builder.example.com"
      assert get_in(report, ["logs", "exit_status"]) == 0

      report_path = opts[:report_path]
      assert File.exists?(report_path)

      {:ok, body} = File.read(report_path)
      assert {:ok, _parsed} = Jason.decode(body)

      File.rm(report_path)
    end

    test "returns failed status on non-zero SSH exit" do
      failing_runner = fn _host, _cmd, _opts ->
        {:ok, %{stdout: "Build failed: rust compile error\n", exit_status: 1}}
      end

      opts =
        base_opts(
          cap_runner: capable_cap_runner(@linux_x64_probe_output),
          ssh_runner: failing_runner
        )

      assert {:ok, report} = RemoteRelease.run(opts)
      assert report["status"] == "failed"
      assert get_in(report, ["logs", "exit_status"]) == 1

      # stdout log written
      stdout_path = get_in(report, ["logs", "stdout_path"])
      assert is_binary(stdout_path)
      assert File.exists?(stdout_path)
      assert File.read!(stdout_path) =~ "rust compile error"

      File.rm(opts[:report_path])
      File.rm(stdout_path)
    end

    test "returns not_buildable report when host lacks required tools" do
      opts =
        base_opts(
          cap_runner: capable_cap_runner(@not_buildable_probe_output),
          ssh_runner: fn _host, _cmd, _opts ->
            flunk("SSH release should not be called when host is not build-capable")
          end
        )

      assert {:ok, report} = RemoteRelease.run(opts)
      assert report["status"] == "not_buildable"
      assert get_in(report, ["capability", "build_capable"]) == false
      missing = get_in(report, ["capability", "missing_tools"])
      assert is_list(missing)
      assert "pnpm" in missing

      File.rm(opts[:report_path])
    end

    test "returns error when capability probe fails" do
      opts =
        base_opts(
          cap_runner: fn _cmd -> {:error, {:ssh_failed, "connection refused"}} end,
          ssh_runner: fn _host, _cmd, _opts -> flunk("should not reach SSH") end
        )

      assert {:error, {:capability_probe_failed, "builder.example.com", _reason}} =
               RemoteRelease.run(opts)
    end

    test "report includes missing_targets comparison" do
      release_runner = fn _host, _cmd, _opts ->
        {:ok, %{stdout: "ok\n", exit_status: 0}}
      end

      opts =
        base_opts(
          cap_runner: capable_cap_runner(@linux_x64_probe_output),
          ssh_runner: release_runner
        )

      {:ok, report} = RemoteRelease.run(opts)
      missing = report["missing_targets"]
      assert is_map(missing)
      assert is_list(missing["published"])
      assert is_list(missing["missing"])

      File.rm(opts[:report_path])
    end
  end

  describe "build_release_command/3" do
    test "command contains the expected mix task and version" do
      params = %{
        version: "4.2.2",
        release_channel: "v4.2.2-rc1",
        plugin: "daisyui_v5",
        bucket: "defdo",
        prefix: "tailwind_cli_daisyui",
        storage_base_url: "https://storage.defdo.de",
        config_provider: "testing",
        overwrite_policy: "fail",
        smoke_test: false,
        verify_upload: false,
        verify_smoke_test: false,
        r2_creds: %{
          access_key_id: "keyid",
          secret_access_key: "secretvalue",
          host: "example.r2.cloudflarestorage.com",
          region: "auto"
        }
      }

      {actual, redacted} = RemoteRelease.build_release_command("/workdir", "linux-x64", params)

      assert String.contains?(actual, "mix tailwind.release")
      assert String.contains?(actual, "--version 4.2.2")
      assert String.contains?(actual, "--channel v4.2.2-rc1")
      assert String.contains?(actual, "--plugin daisyui_v5")
      assert String.contains?(actual, "cd /workdir")

      # Actual command has the real secret
      assert String.contains?(actual, "keyid")
      assert String.contains?(actual, "secretvalue")

      # Redacted command hides secrets
      refute String.contains?(redacted, "keyid")
      refute String.contains?(redacted, "secretvalue")
      assert String.contains?(redacted, "[REDACTED]")
    end

    test "includes --smoke-test flag when enabled" do
      params = %{
        version: "4.2.2",
        release_channel: "v4.2.2-rc1",
        plugin: "daisyui_v5",
        bucket: "defdo",
        prefix: "tailwind_cli_daisyui",
        storage_base_url: "https://storage.defdo.de",
        config_provider: "testing",
        overwrite_policy: "fail",
        smoke_test: true,
        verify_upload: true,
        verify_smoke_test: true,
        r2_creds: nil
      }

      {actual, _redacted} = RemoteRelease.build_release_command("/workdir", "linux-x64", params)

      assert String.contains?(actual, "--smoke-test")
      assert String.contains?(actual, "--verify-upload")
      assert String.contains?(actual, "--verify-smoke-test")
    end

    test "omits --smoke-test when disabled" do
      params = %{
        version: "4.2.2",
        release_channel: "v4.2.2-rc1",
        plugin: "daisyui_v5",
        bucket: "defdo",
        prefix: "tailwind_cli_daisyui",
        storage_base_url: "https://storage.defdo.de",
        config_provider: "testing",
        overwrite_policy: "fail",
        smoke_test: false,
        verify_upload: false,
        verify_smoke_test: false,
        r2_creds: nil
      }

      {actual, _redacted} = RemoteRelease.build_release_command("/workdir", "linux-x64", params)

      refute String.contains?(actual, "--smoke-test")
      refute String.contains?(actual, "--verify-upload")
    end
  end

  describe "report JSON shape" do
    test "all top-level schema_version 1 keys are present" do
      release_runner = fn _host, _cmd, _opts ->
        {:ok, %{stdout: "ok\n", exit_status: 0}}
      end

      opts =
        base_opts(
          cap_runner: capable_cap_runner(@linux_x64_probe_output),
          ssh_runner: release_runner
        )

      {:ok, report} = RemoteRelease.run(opts)

      required_keys = ~w(schema_version executed_at release_channel tailwind_version
                         tailwind_cli_version plugin remote capability status
                         artifact verification logs missing_targets)

      for key <- required_keys do
        assert Map.has_key?(report, key), "Missing report key: #{key}"
      end

      assert report["schema_version"] == 1
      assert is_binary(report["executed_at"])

      File.rm(opts[:report_path])
    end
  end
end
