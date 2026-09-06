defmodule Defdo.TailwindBuilder.ReleaseCatalogTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Deployer

  @sample_manifest_path Path.expand("../../../docs/sample_manifest.v4.2.2-rc1.json", __DIR__)

  defp sample_manifest do
    @sample_manifest_path |> File.read!() |> Jason.decode!()
  end

  defp publish(entries) do
    Deployer.publish_release_catalog(entries: entries, dry_run: true)
  end

  defp catalog_entries(body) do
    body |> Jason.decode!() |> Map.fetch!("versions")
  end

  describe "publish_release_catalog/1 (dry run)" do
    test "builds a productivo entry from the sample manifest" do
      manifest = sample_manifest()

      assert {:ok, result} =
               publish([
                 %{manifest: manifest, status: "productivo", url_prefix: "tailwind_cli_daisyui"}
               ])

      assert result.versions == 1
      assert [entry] = catalog_entries(result.body)

      assert Enum.sort(Map.keys(entry)) ==
               Enum.sort(
                 ~w(version tailwind_version flavor status published_at url metadata hash)
               )

      assert entry["version"] == "4.2.2-daisyui"
      assert entry["tailwind_version"] == "4.2.2"
      assert entry["flavor"] == "daisyui"
      assert entry["status"] == "productivo"
      assert entry["published_at"] == "2026-06-28T00:00:00.000000Z"

      assert String.ends_with?(
               entry["url"],
               "/tailwind_cli_daisyui/v$version/tailwindcss-$target"
             )

      assert entry["metadata"]["daisyui_version"] == "5.5.19"

      for {_target, hash} <- entry["hash"] do
        assert hash["sha256"] =~ ~r/^[0-9a-f]{64}$/
      end

      expected_targets =
        Enum.map(manifest["files"], fn file ->
          case file["target_key"] do
            "windows-x64" -> "windows-x64.exe"
            target_key -> target_key
          end
        end)

      assert Enum.sort(Map.keys(entry["hash"])) == Enum.sort(expected_targets)
    end

    test "in_progress entry without files has an empty hash" do
      manifest = %{"tailwind_version" => "4.3.4-rc1", "files" => []}

      assert {:ok, result} =
               publish([
                 %{
                   manifest: manifest,
                   status: "in_progress",
                   url_prefix: "tailwind_cli_daisyui_ci_canary"
                 }
               ])

      assert [entry] = catalog_entries(result.body)
      assert entry["status"] == "in_progress"
      assert entry["hash"] == %{}
    end

    test "productivo entry without files is an error" do
      manifest = %{"tailwind_version" => "4.3.3", "files" => []}

      assert {:error, {:no_files, "4.3.3-daisyui"}} =
               publish([
                 %{manifest: manifest, status: "productivo", url_prefix: "tailwind_cli_daisyui"}
               ])
    end

    test "unknown status is an error" do
      manifest = sample_manifest()

      assert {:error, {:invalid_status, "staging"}} =
               publish([
                 %{manifest: manifest, status: "staging", url_prefix: "tailwind_cli_daisyui"}
               ])
    end

    test "entries are sorted newest first" do
      older = %{
        "tailwind_version" => "4.3.2",
        "built_at" => "2026-01-01T00:00:00Z",
        "files" => []
      }

      # Atom keys, like a manifest built in code rather than decoded from JSON.
      newer = %{
        tailwind_version: "4.3.3",
        built_at: "2026-06-01T00:00:00Z",
        plugin_set: [%{name: "daisyui", version: "5.7.4"}],
        files: [
          %{
            target_key: "windows-x64",
            checksum_sha256: String.duplicate("ab", 32),
            built_at: "2026-06-01T00:00:00Z"
          }
        ]
      }

      assert {:ok, result} =
               publish([
                 %{manifest: older, status: "in_progress", url_prefix: "tailwind_cli_daisyui"},
                 %{manifest: newer, status: "in_progress", url_prefix: "tailwind_cli_daisyui"}
               ])

      assert [first, second] = catalog_entries(result.body)
      assert first["tailwind_version"] == "4.3.3"
      assert first["published_at"] == "2026-06-01T00:00:00Z"
      assert first["metadata"]["daisyui_version"] == "5.7.4"
      assert Map.keys(first["hash"]) == ["windows-x64.exe"]
      assert second["tailwind_version"] == "4.3.2"
      assert second["published_at"] == "2026-01-01T00:00:00Z"
    end

    test "dry run does not upload and reports the url" do
      manifest = sample_manifest()

      assert {:ok, result} =
               publish([
                 %{manifest: manifest, status: "productivo", url_prefix: "tailwind_cli_daisyui"}
               ])

      assert result.url == "https://storage.defdo.de/tailwind_cli_daisyui/releases.json"
      assert result.versions == 1
      assert is_binary(result.body)
    end
  end
end
