defmodule Mix.Tasks.Tailwind.ReleaseTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Mock

  alias Defdo.TailwindBuilder.ConfigProviders.TestingConfigProvider
  alias Mix.Tasks.Tailwind.Release, as: TailwindReleaseTask

  setup do
    original_env = %{
      r2_access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
      r2_secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
      r2_host: System.get_env("R2_HOST"),
      r2_region: System.get_env("R2_REGION"),
      aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      aws_region: System.get_env("AWS_REGION")
    }

    original_storage = Application.get_env(:tailwind_builder, :storage)

    System.put_env("R2_ACCESS_KEY_ID", "test-access-key")
    System.put_env("R2_SECRET_ACCESS_KEY", "test-secret-key")
    System.put_env("R2_HOST", "example.r2.cloudflarestorage.com")
    System.put_env("R2_REGION", "auto")
    System.delete_env("AWS_ACCESS_KEY_ID")
    System.delete_env("AWS_SECRET_ACCESS_KEY")
    System.delete_env("AWS_REGION")

    Mix.Task.reenable("app.start")
    Mix.Task.reenable("tailwind.release")

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} ->
        env_key = key |> Atom.to_string() |> String.upcase()

        if value do
          System.put_env(env_key, value)
        else
          System.delete_env(env_key)
        end
      end)

      if original_storage do
        Application.put_env(:tailwind_builder, :storage, original_storage)
      else
        Application.delete_env(:tailwind_builder, :storage)
      end

      Mix.Task.reenable("app.start")
      Mix.Task.reenable("tailwind.release")
    end)

    :ok
  end

  describe "run/1" do
    test "passes parsed options to the release flow" do
      parent = self()

      with_mock Defdo.TailwindBuilder.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})

          {:ok,
           %{
             version: Keyword.fetch!(opts, :version),
             release_channel: Keyword.fetch!(opts, :release_channel),
             source_path: Keyword.get(opts, :source_path, "/tmp/tailwind"),
             deploy: %{
               binaries_deployed: 3,
               manifest: %{},
               sha256sums: "abc123  tailwindcss-linux-x64"
             }
           }}
        end do
        output =
          capture_io(fn ->
            TailwindReleaseTask.run([
              "--version",
              "4.2.2",
              "--channel",
              "v4.2.2-rc1",
              "--source-path",
              "/tmp/tailwind-4.2.2",
              "--bucket",
              "defdo",
              "--prefix",
              "tailwind_cli_daisyui",
              "--storage-base-url",
              "https://storage.defdo.de",
              "--destination",
              "r2",
              "--config-provider",
              "testing",
              "--plugin",
              "daisyui_v5",
              "--plugin",
              "@tailwindcss/typography",
              "--smoke-test"
            ])
          end)

        assert output =~ "Release completed successfully"
        assert output =~ "Version: 4.2.2"
        assert output =~ "Channel: v4.2.2-rc1"

        assert_received {:release_opts, release_opts}
        assert release_opts[:version] == "4.2.2"
        assert release_opts[:release_channel] == "v4.2.2-rc1"
        assert release_opts[:source_path] == "/tmp/tailwind-4.2.2"
        assert release_opts[:bucket] == "defdo"
        assert release_opts[:prefix] == "tailwind_cli_daisyui"
        assert release_opts[:storage_base_url] == "https://storage.defdo.de"
        assert release_opts[:destination] == :r2
        assert release_opts[:config_provider] == TestingConfigProvider
        assert release_opts[:plugins] == ["daisyui_v5", "@tailwindcss/typography"]
        assert release_opts[:smoke_test_binaries] == true
      end
    end

    test "passes --verify-upload through to the release flow" do
      parent = self()

      with_mock Defdo.TailwindBuilder.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})

          {:ok,
           %{
             version: Keyword.fetch!(opts, :version),
             release_channel: Keyword.fetch!(opts, :release_channel),
             source_path: "/tmp/tailwind-4.2.2",
             deploy: %{
               binaries_deployed: 1,
               manifest: %{},
               sha256sums: "abc123  tailwindcss-linux-x64"
             }
           }}
        end do
        capture_io(fn ->
          TailwindReleaseTask.run([
            "--version",
            "4.2.2",
            "--channel",
            "v4.2.2-rc1",
            "--config-provider",
            "testing",
            "--verify-upload"
          ])
        end)

        assert_received {:release_opts, release_opts}
        assert release_opts[:verify_upload] == true
      end
    end

    test "defaults verify_upload to false when --verify-upload is omitted" do
      parent = self()

      with_mock Defdo.TailwindBuilder.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})

          {:ok,
           %{
             version: Keyword.fetch!(opts, :version),
             release_channel: Keyword.fetch!(opts, :release_channel),
             source_path: "/tmp/tailwind-4.2.2",
             deploy: %{
               binaries_deployed: 1,
               manifest: %{},
               sha256sums: "abc123  tailwindcss-linux-x64"
             }
           }}
        end do
        capture_io(fn ->
          TailwindReleaseTask.run([
            "--version",
            "4.2.2",
            "--channel",
            "v4.2.2-rc1",
            "--config-provider",
            "testing"
          ])
        end)

        assert_received {:release_opts, release_opts}
        assert release_opts[:verify_upload] == false
      end
    end

    test "passes --dry-run and --overwrite-policy through to the release flow" do
      parent = self()

      with_mock Defdo.TailwindBuilder.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})

          {:ok,
           %{
             version: Keyword.fetch!(opts, :version),
             release_channel: Keyword.fetch!(opts, :release_channel),
             source_path: "/tmp/tailwind-4.2.2",
             dry_run: Keyword.get(opts, :dry_run, false),
             deploy: %{
               binaries_deployed: 1,
               manifest: %{},
               sha256sums: "abc123  tailwindcss-linux-x64"
             }
           }}
        end do
        output =
          capture_io(fn ->
            TailwindReleaseTask.run([
              "--version",
              "4.2.2",
              "--channel",
              "v4.2.2-rc1",
              "--config-provider",
              "testing",
              "--dry-run",
              "--overwrite-policy",
              "promote_only"
            ])
          end)

        assert output =~ "dry run"

        assert_received {:release_opts, release_opts}
        assert release_opts[:dry_run] == true
        assert release_opts[:overwrite_policy] == :promote_only
      end
    end

    test "rejects an unsupported overwrite policy" do
      assert_raise Mix.Error, fn ->
        capture_io(fn ->
          TailwindReleaseTask.run([
            "--config-provider",
            "testing",
            "--overwrite-policy",
            "bogus"
          ])
        end)
      end
    end

    test "raises for unsupported config providers" do
      assert_raise Mix.Error, fn ->
        capture_io(fn ->
          TailwindReleaseTask.run(["--config-provider", "unknown"])
        end)
      end
    end

    test "accepts AWS-style credentials as fallback for S3-compatible environments" do
      parent = self()

      System.delete_env("R2_ACCESS_KEY_ID")
      System.delete_env("R2_SECRET_ACCESS_KEY")
      System.delete_env("R2_REGION")
      System.put_env("AWS_ACCESS_KEY_ID", "fallback-access-key")
      System.put_env("AWS_SECRET_ACCESS_KEY", "fallback-secret-key")
      System.put_env("AWS_REGION", "auto")

      with_mock Defdo.TailwindBuilder.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})

          {:ok,
           %{
             version: Keyword.fetch!(opts, :version),
             release_channel: Keyword.fetch!(opts, :release_channel),
             source_path: "/tmp/tailwind-4.2.2",
             deploy: %{
               binaries_deployed: 1,
               manifest: %{},
               sha256sums: "abc123  tailwindcss-linux-x64"
             }
           }}
        end do
        capture_io(fn ->
          TailwindReleaseTask.run([
            "--version",
            "4.2.2",
            "--channel",
            "v4.2.2-rc1",
            "--config-provider",
            "testing"
          ])
        end)

        assert_received {:release_opts, _release_opts}

        assert Application.get_env(:tailwind_builder, :storage)[:access_key_id] ==
                 "fallback-access-key"

        assert Application.get_env(:tailwind_builder, :storage)[:secret_access_key] ==
                 "fallback-secret-key"

        assert Application.get_env(:tailwind_builder, :storage)[:region] == "auto"
      end
    end

    test "normalizes R2_HOST when it includes https:// prefix" do
      parent = self()

      System.put_env("R2_HOST", "https://example.r2.cloudflarestorage.com")

      with_mock Defdo.TailwindBuilder.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})

          {:ok,
           %{
             version: Keyword.fetch!(opts, :version),
             release_channel: Keyword.fetch!(opts, :release_channel),
             source_path: "/tmp/tailwind-4.2.2",
             deploy: %{
               binaries_deployed: 1,
               manifest: %{},
               sha256sums: "abc123  tailwindcss-linux-x64"
             }
           }}
        end do
        capture_io(fn ->
          TailwindReleaseTask.run([
            "--version",
            "4.2.2",
            "--channel",
            "v4.2.2-rc1",
            "--config-provider",
            "testing"
          ])
        end)

        assert_received {:release_opts, _release_opts}

        assert Application.get_env(:tailwind_builder, :storage)[:host] ==
                 "example.r2.cloudflarestorage.com"
      end
    end

    test "normalizes R2_HOST with trailing slash" do
      parent = self()

      System.put_env("R2_HOST", "example.r2.cloudflarestorage.com/")

      with_mock Defdo.TailwindBuilder.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})

          {:ok,
           %{
             version: Keyword.fetch!(opts, :version),
             release_channel: Keyword.fetch!(opts, :release_channel),
             source_path: "/tmp/tailwind-4.2.2",
             deploy: %{
               binaries_deployed: 1,
               manifest: %{},
               sha256sums: "abc123  tailwindcss-linux-x64"
             }
           }}
        end do
        capture_io(fn ->
          TailwindReleaseTask.run([
            "--version",
            "4.2.2",
            "--channel",
            "v4.2.2-rc1",
            "--config-provider",
            "testing"
          ])
        end)

        assert_received {:release_opts, _release_opts}

        assert Application.get_env(:tailwind_builder, :storage)[:host] ==
                 "example.r2.cloudflarestorage.com"
      end
    end

    test "keeps bare R2_HOST unchanged" do
      parent = self()

      System.put_env("R2_HOST", "example.r2.cloudflarestorage.com")

      with_mock Defdo.TailwindBuilder.Release, [],
        run: fn opts ->
          send(parent, {:release_opts, opts})

          {:ok,
           %{
             version: Keyword.fetch!(opts, :version),
             release_channel: Keyword.fetch!(opts, :release_channel),
             source_path: "/tmp/tailwind-4.2.2",
             deploy: %{
               binaries_deployed: 1,
               manifest: %{},
               sha256sums: "abc123  tailwindcss-linux-x64"
             }
           }}
        end do
        capture_io(fn ->
          TailwindReleaseTask.run([
            "--version",
            "4.2.2",
            "--channel",
            "v4.2.2-rc1",
            "--config-provider",
            "testing"
          ])
        end)

        assert_received {:release_opts, _release_opts}

        assert Application.get_env(:tailwind_builder, :storage)[:host] ==
                 "example.r2.cloudflarestorage.com"
      end
    end
  end
end
