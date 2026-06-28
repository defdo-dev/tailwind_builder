defmodule Mix.Tasks.Tailwind.Release.RemoteTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Mock

  alias Mix.Tasks.Tailwind.Release.Remote, as: RemoteTask

  setup do
    Mix.Task.reenable("app.start")
    Mix.Task.reenable("tailwind.release.remote")

    on_exit(fn ->
      Mix.Task.reenable("app.start")
      Mix.Task.reenable("tailwind.release.remote")
    end)

    :ok
  end

  defp published_report(host, workdir, target_key \\ "linux-x64") do
    %{
      "schema_version" => 1,
      "executed_at" => "2026-06-27T00:00:00Z",
      "release_channel" => "v4.2.2-rc1",
      "tailwind_version" => "4.2.2",
      "tailwind_cli_version" => "4.2.2",
      "plugin" => "daisyui_v5",
      "remote" => %{
        "host" => host,
        "workdir" => workdir,
        "hostname" => "builder",
        "os" => "linux",
        "arch" => "x86_64"
      },
      "capability" => %{
        "target_key" => target_key,
        "build_capable" => true,
        "missing_tools" => []
      },
      "status" => "published",
      "artifact" => nil,
      "verification" => %{"upload_verified" => false, "status" => "skipped"},
      "logs" => %{"stdout_path" => "/tmp/log.txt", "exit_status" => 0},
      "missing_targets" => %{
        "published" => [target_key],
        "missing" => [],
        "buildable_now" => [],
        "failed" => []
      }
    }
  end

  defp not_buildable_report(host, workdir) do
    %{
      "schema_version" => 1,
      "executed_at" => "2026-06-27T00:00:00Z",
      "release_channel" => "v4.2.2-rc1",
      "tailwind_version" => "4.2.2",
      "tailwind_cli_version" => "4.2.2",
      "plugin" => "daisyui_v5",
      "remote" => %{
        "host" => host,
        "workdir" => workdir,
        "hostname" => "partial",
        "os" => "linux",
        "arch" => "x86_64"
      },
      "capability" => %{
        "target_key" => "linux-x64",
        "build_capable" => false,
        "missing_tools" => ["pnpm", "bun", "rustc"]
      },
      "status" => "not_buildable",
      "artifact" => nil,
      "verification" => %{"upload_verified" => false, "status" => "skipped"},
      "logs" => %{"stdout_path" => nil, "exit_status" => nil},
      "missing_targets" => %{
        "published" => [],
        "missing" => ["linux-x64"],
        "buildable_now" => [],
        "failed" => []
      }
    }
  end

  describe "run/1 option parsing" do
    test "parses all options and passes them to RemoteRelease.run/1" do
      parent = self()

      with_mock Defdo.TailwindBuilder.Remote.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})
          {:ok, published_report(opts[:host], opts[:workdir])}
        end do
        capture_io(fn ->
          RemoteTask.run([
            "--host",
            "builder.example.com",
            "--workdir",
            "/home/build/tailwind_builder",
            "--version",
            "4.2.2",
            "--channel",
            "v4.2.2-rc1",
            "--config-provider",
            "testing",
            "--bucket",
            "defdo",
            "--prefix",
            "tailwind_cli_daisyui",
            "--storage-base-url",
            "https://storage.defdo.de",
            "--plugin",
            "daisyui_v5",
            "--smoke-test",
            "--verify-upload",
            "--overwrite-policy",
            "fail"
          ])
        end)

        assert_received {:release_opts, opts}
        assert opts[:host] == "builder.example.com"
        assert opts[:workdir] == "/home/build/tailwind_builder"
        assert opts[:version] == "4.2.2"
        assert opts[:release_channel] == "v4.2.2-rc1"
        assert opts[:plugin] == "daisyui_v5"
        assert opts[:smoke_test] == true
        assert opts[:verify_upload] == true
        assert opts[:overwrite_policy] == "fail"
      end
    end

    test "raises Mix.Error when --host is missing" do
      assert_raise Mix.Error, ~r/--host/, fn ->
        capture_io(fn ->
          RemoteTask.run(["--workdir", "/workdir"])
        end)
      end
    end

    test "raises Mix.Error when --workdir is missing" do
      assert_raise Mix.Error, ~r/--workdir/, fn ->
        capture_io(fn ->
          RemoteTask.run(["--host", "example.com"])
        end)
      end
    end
  end

  describe "run/1 output" do
    test "prints success message for published status" do
      with_mock Defdo.TailwindBuilder.Remote.Release, [],
        run: fn opts -> {:ok, published_report(opts[:host], opts[:workdir])} end do
        output =
          capture_io(fn ->
            RemoteTask.run([
              "--host",
              "builder.example.com",
              "--workdir",
              "/workdir"
            ])
          end)

        assert output =~ "succeeded"
      end
    end

    test "prints not_buildable info for not_buildable status" do
      with_mock Defdo.TailwindBuilder.Remote.Release, [],
        run: fn opts -> {:ok, not_buildable_report(opts[:host], opts[:workdir])} end do
        output =
          capture_io(fn ->
            RemoteTask.run([
              "--host",
              "builder.example.com",
              "--workdir",
              "/workdir"
            ])
          end)

        assert output =~ "not build-capable"
      end
    end

    test "raises Mix.Error for failed status" do
      failed_report = %{
        "schema_version" => 1,
        "status" => "failed",
        "release_channel" => "v4.2.2-rc1",
        "tailwind_version" => "4.2.2",
        "tailwind_cli_version" => "4.2.2",
        "plugin" => "daisyui_v5",
        "remote" => %{"host" => "builder.example.com", "workdir" => "/workdir"},
        "capability" => %{
          "target_key" => "linux-x64",
          "build_capable" => true,
          "missing_tools" => []
        },
        "artifact" => nil,
        "verification" => %{"status" => "skipped"},
        "logs" => %{"stdout_path" => "/tmp/log.txt", "exit_status" => 1},
        "missing_targets" => %{}
      }

      with_mock Defdo.TailwindBuilder.Remote.Release, [],
        run: fn _opts -> {:ok, failed_report} end do
        assert_raise Mix.Error, ~r/failed/, fn ->
          capture_io(fn ->
            RemoteTask.run([
              "--host",
              "builder.example.com",
              "--workdir",
              "/workdir"
            ])
          end)
        end
      end
    end

    test "raises Mix.Error on release error" do
      with_mock Defdo.TailwindBuilder.Remote.Release, [],
        run: fn _opts -> {:error, {:capability_probe_failed, "builder.example.com", :timeout}} end do
        assert_raise Mix.Error, fn ->
          capture_io(fn ->
            RemoteTask.run([
              "--host",
              "builder.example.com",
              "--workdir",
              "/workdir"
            ])
          end)
        end
      end
    end
  end
end
