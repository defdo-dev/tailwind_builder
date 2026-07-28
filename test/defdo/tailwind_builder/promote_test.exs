defmodule Defdo.TailwindBuilder.PromoteTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Defdo.TailwindBuilder.Deployer

  test "promote_channel surfaces a source-manifest fetch failure without touching R2" do
    fetcher = fn _url -> {:error, :nope} end

    assert {:error, :nope} =
             Deployer.promote_channel(channel: "v4.3.2-rc1", fetcher: fetcher)
  end

  test "promote_channel rejects an unparseable source manifest" do
    fetcher = fn _url -> {:ok, "not-json"} end

    assert {:error, %Jason.DecodeError{}} =
             Deployer.promote_channel(channel: "v4.3.2-rc1", fetcher: fetcher)
  end

  describe "promotion file gate" do
    setup do
      original = Application.get_env(:tailwind_builder, :storage)

      Application.put_env(:tailwind_builder, :storage,
        access_key_id: "test-key",
        secret_access_key: "test-secret",
        host: "test.r2.invalid",
        region: "auto"
      )

      on_exit(fn ->
        if original,
          do: Application.put_env(:tailwind_builder, :storage, original),
          else: Application.delete_env(:tailwind_builder, :storage)
      end)

      :ok
    end

    defp manifest_with(files) do
      Jason.encode!(%{"version" => "4.3.3", "files" => files})
    end

    defp promote_with(files, extra \\ []) do
      fetcher = fn _url -> {:ok, manifest_with(files)} end

      [channel: "v4.3.3-rc1", fetcher: fetcher, head_checker: fn _url -> true end]
      |> Keyword.merge(extra)
      |> Deployer.promote_channel()
    end

    test "blocks files with an explicitly failed plugin check" do
      files = [
        %{
          "filename" => "tailwindcss-linux-x64",
          "plugin_checks" => [%{"plugin" => "daisyui", "status" => "failed"}]
        }
      ]

      assert {:error, {:promotion_blocked, {:failed_plugin_checks, [entry]}}} =
               promote_with(files)

      assert entry.filename == "tailwindcss-linux-x64"
      assert entry.plugin == "daisyui"
    end

    test "blocks files whose artifact is not reachable" do
      files = [
        %{
          "filename" => "tailwindcss-linux-x64-musl",
          "storage_url" => "https://storage.defdo.de/gone/tailwindcss-linux-x64-musl",
          "plugin_checks" => []
        }
      ]

      assert {:error,
              {:promotion_blocked, {:artifacts_unreachable, ["tailwindcss-linux-x64-musl"]}}} =
               promote_with(files, head_checker: fn _url -> false end)
    end

    test "unprobed artifacts warn loudly but do not block (cross-compiled reality)" do
      files = [
        %{
          "filename" => "tailwindcss-linux-x64-musl",
          "storage_url" => "https://storage.defdo.de/x/tailwindcss-linux-x64-musl",
          "plugin_checks" => []
        }
      ]

      log =
        capture_log(fn ->
          # The guard passes; the run then dies in copy_objects (no storage
          # configured in tests) — anything but a gate rejection proves passage.
          result = promote_with(files)
          refute match?({:error, {:promotion_blocked, _}}, result)
        end)

      assert log =~ "unprobed artifacts"
      assert log =~ "tailwindcss-linux-x64-musl"
    end

    test "verified files pass the gate (then fail later without test storage)" do
      files = [
        %{
          "filename" => "tailwindcss-macos-arm64",
          "storage_url" => "https://storage.defdo.de/x/tailwindcss-macos-arm64",
          "plugin_checks" => [%{"plugin" => "daisyui", "status" => "verified"}]
        }
      ]

      result = promote_with(files)
      refute match?({:error, {:promotion_blocked, _}}, result)
    end
  end
end
