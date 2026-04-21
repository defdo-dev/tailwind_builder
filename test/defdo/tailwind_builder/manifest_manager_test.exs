defmodule Defdo.TailwindBuilder.ManifestManagerTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindBuilder.ManifestManager

  @version "4.1.14"
  @expected_targets ["linux-x64", "macos-arm64"]

  setup do
    root = Path.join(System.tmp_dir!(), "tailwind_manifest_#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf(root)
    end)

    {:ok, root: root}
  end

  describe "canonical_target/1" do
    test "normalizes common aliases and rust triples" do
      assert ManifestManager.canonical_target("darwin-arm64") == "macos-arm64"
      assert ManifestManager.canonical_target("x86_64-unknown-linux-gnu") == "linux-x64"
      assert ManifestManager.canonical_target("x86_64-unknown-linux-musl") == "linux-musl-x64"
      assert ManifestManager.canonical_target(:"x86_64-pc-windows-msvc") == "win32-x64"
    end
  end

  describe "upsert_post_build/1" do
    test "creates build and release manifests from scratch", %{root: root} do
      paths = build_paths(root)
      artifact_path = write_artifact(paths.dist_dir, "tailwindcss-linux-x64", "linux-x64 v1")
      expected_hash = checksum_map("linux-x64 v1")

      assert {:ok, result} =
               ManifestManager.upsert_post_build(
                 version: @version,
                 source_path: root,
                 standalone_root: paths.standalone_root,
                 target: "linux-x64",
                 flavor: "standalone",
                 expected_targets: @expected_targets
               )

      assert result.status == :updated
      assert result.target == "linux-x64"

      build_manifest = read_manifest(paths.build_manifest_path)
      release_manifest = read_manifest(paths.release_manifest_path)

      assert build_manifest["version"] == @version
      assert build_manifest["flavor"] == "standalone"
      assert build_manifest["build_status"] == "partial"
      assert build_manifest["expected_targets"] == @expected_targets
      assert build_manifest["available_targets"] == ["linux-x64"]
      assert build_manifest["missing_targets"] == ["macos-arm64"]
      assert build_manifest["split_hint"]["target"] == "linux-x64"
      assert build_manifest["nodes"] == []
      assert build_manifest["workers"] == []

      assert build_manifest["targets"]["linux-x64"]["artifact"]["filename"] ==
               "tailwindcss-linux-x64"

      assert build_manifest["targets"]["linux-x64"]["hash"] == expected_hash

      assert release_manifest["version"] == @version
      assert release_manifest["flavor"] == "standalone"
      assert release_manifest["status"] == "partial"
      assert release_manifest["includes"] == ["linux-x64"]
      assert release_manifest["published_at"] != nil
      assert release_manifest["hash"]["linux-x64"] == expected_hash
      assert release_manifest["metadata"]["compilation_method"] == "pnpm_workspace"
      assert release_manifest["metadata"]["expected_targets"] == @expected_targets
      assert release_manifest["metadata"]["available_targets"] == ["linux-x64"]
      assert release_manifest["metadata"]["missing_targets"] == ["macos-arm64"]

      assert release_manifest["metadata"]["targets"]["linux-x64"]["artifact"]["relative_path"] ==
               "dist/tailwindcss-linux-x64"

      assert File.exists?(artifact_path)
    end

    test "does not rewrite manifests when the target hash is unchanged", %{root: root} do
      paths = build_paths(root)
      write_artifact(paths.dist_dir, "tailwindcss-linux-x64", "linux-x64 v1")

      assert {:ok, first_result} =
               ManifestManager.upsert_post_build(
                 version: @version,
                 source_path: root,
                 standalone_root: paths.standalone_root,
                 target: "linux-x64",
                 flavor: "standalone",
                 expected_targets: @expected_targets
               )

      assert first_result.status == :updated

      build_before = File.read!(paths.build_manifest_path)
      release_before = File.read!(paths.release_manifest_path)

      assert {:ok, second_result} =
               ManifestManager.upsert_post_build(
                 version: @version,
                 source_path: root,
                 standalone_root: paths.standalone_root,
                 target: "linux-x64",
                 flavor: "standalone",
                 expected_targets: @expected_targets
               )

      assert second_result.status == :unchanged
      assert File.read!(paths.build_manifest_path) == build_before
      assert File.read!(paths.release_manifest_path) == release_before
    end

    test "updates only the changed target entry", %{root: root} do
      paths = build_paths(root)
      write_artifact(paths.dist_dir, "tailwindcss-linux-x64", "linux-x64 v1")
      macos_path = write_artifact(paths.dist_dir, "tailwindcss-macos-arm64", "macos-arm64 v1")

      assert {:ok, _} =
               ManifestManager.upsert_post_build(
                 version: @version,
                 source_path: root,
                 standalone_root: paths.standalone_root,
                 target: "linux-x64",
                 flavor: "standalone",
                 expected_targets: @expected_targets
               )

      assert {:ok, _} =
               ManifestManager.upsert_post_build(
                 version: @version,
                 source_path: root,
                 standalone_root: paths.standalone_root,
                 target: "macos-arm64",
                 flavor: "standalone",
                 expected_targets: @expected_targets
               )

      linux_before = read_manifest(paths.build_manifest_path)["targets"]["linux-x64"]["hash"]

      File.write!(macos_path, "macos-arm64 v2")
      expected_macos_hash = checksum_map("macos-arm64 v2")

      assert {:ok, result} =
               ManifestManager.upsert_post_build(
                 version: @version,
                 source_path: root,
                 standalone_root: paths.standalone_root,
                 target: "macos-arm64",
                 flavor: "standalone",
                 expected_targets: @expected_targets
               )

      assert result.status == :updated

      build_manifest = read_manifest(paths.build_manifest_path)
      release_manifest = read_manifest(paths.release_manifest_path)

      assert build_manifest["build_status"] == "complete"
      assert build_manifest["available_targets"] == ["linux-x64", "macos-arm64"]
      assert build_manifest["missing_targets"] == []
      assert build_manifest["targets"]["linux-x64"]["hash"] == linux_before
      assert build_manifest["targets"]["macos-arm64"]["hash"] == expected_macos_hash

      assert release_manifest["status"] == "complete"
      assert release_manifest["includes"] == ["linux-x64", "macos-arm64"]
      assert release_manifest["hash"]["linux-x64"] == linux_before
      assert release_manifest["hash"]["macos-arm64"] == expected_macos_hash
    end

    test "merges concurrent target updates without losing entries", %{root: root} do
      paths = build_paths(root)
      write_artifact(paths.dist_dir, "tailwindcss-linux-x64", "linux-x64 concurrent")
      write_artifact(paths.dist_dir, "tailwindcss-macos-arm64", "macos-arm64 concurrent")

      tasks = [
        fn ->
          ManifestManager.upsert_post_build(
            version: @version,
            source_path: root,
            standalone_root: paths.standalone_root,
            target: "linux-x64",
            flavor: "standalone",
            expected_targets: @expected_targets
          )
        end,
        fn ->
          ManifestManager.upsert_post_build(
            version: @version,
            source_path: root,
            standalone_root: paths.standalone_root,
            target: "macos-arm64",
            flavor: "standalone",
            expected_targets: @expected_targets
          )
        end
      ]

      results =
        tasks
        |> Task.async_stream(fn fun -> fun.() end,
          max_concurrency: 2,
          ordered: false,
          timeout: 30_000
        )
        |> Enum.to_list()

      assert Enum.all?(results, fn
               {:ok, {:ok, _}} -> true
               _ -> false
             end)

      build_manifest = read_manifest(paths.build_manifest_path)
      release_manifest = read_manifest(paths.release_manifest_path)

      assert build_manifest["build_status"] == "complete"
      assert build_manifest["available_targets"] == ["linux-x64", "macos-arm64"]
      assert build_manifest["missing_targets"] == []
      assert Map.has_key?(build_manifest["targets"], "linux-x64")
      assert Map.has_key?(build_manifest["targets"], "macos-arm64")

      assert release_manifest["status"] == "complete"
      assert release_manifest["includes"] == ["linux-x64", "macos-arm64"]
      assert Map.has_key?(release_manifest["hash"], "linux-x64")
      assert Map.has_key?(release_manifest["hash"], "macos-arm64")
    end
  end

  defp build_paths(root) do
    tailwind_root = Path.join(root, "tailwindcss-#{@version}")

    standalone_root =
      Path.join([tailwind_root, "packages", "@tailwindcss-standalone"])

    dist_dir = Path.join(standalone_root, "dist")
    File.mkdir_p!(dist_dir)

    %{
      tailwind_root: tailwind_root,
      standalone_root: standalone_root,
      dist_dir: dist_dir,
      build_manifest_path: Path.join(dist_dir, "build-manifest.json"),
      release_manifest_path: Path.join(dist_dir, "release-manifest.json")
    }
  end

  defp write_artifact(dist_dir, filename, content) do
    path = Path.join(dist_dir, filename)
    File.write!(path, content)
    path
  end

  defp read_manifest(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp checksum_map(content) do
    %{
      "sha256" => Base.encode16(:crypto.hash(:sha256, content), case: :lower),
      "md5" => Base.encode16(:crypto.hash(:md5, content), case: :lower)
    }
  end
end
