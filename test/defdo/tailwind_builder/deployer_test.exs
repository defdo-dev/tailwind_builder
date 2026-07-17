defmodule Defdo.TailwindBuilder.DeployerTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Core.{ArchitectureMatrix, Targets}
  alias Defdo.TailwindBuilder.Deployer

  defp temp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  defp write_file(dir, filename, contents) do
    path = Path.join(dir, filename)
    File.write!(path, contents)
    path
  end

  describe "generate_deployment_manifest/3" do
    test "includes canonical target metadata, checksums, and storage urls" do
      dir = temp_dir("deployer_manifest")
      on_exit(fn -> File.rm_rf(dir) end)

      macos_binary = write_file(dir, "tailwindcss-macos-arm64", "macos binary contents")
      linux_binary = write_file(dir, "tailwindcss-linux-x64", "linux binary contents")

      deployed_files = [
        {:ok,
         %{
           local_path: macos_binary,
           remote_key: "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-macos-arm64",
           bucket: "defdo",
           size: File.stat!(macos_binary).size
         }},
        {:ok,
         %{
           local_path: linux_binary,
           remote_key: "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
           bucket: "defdo",
           size: File.stat!(linux_binary).size
         }}
      ]

      {:ok, manifest} =
        Deployer.generate_deployment_manifest(
          deployed_files,
          "4.2.2",
          release_channel: "v4.2.2-rc1",
          plugin_set: [%{name: "daisyui", version: "5.5.19"}],
          storage_base_url: "https://storage.defdo.de",
          built_at: "2026-03-20T00:00:00Z"
        )

      assert manifest.version == "4.2.2"
      assert manifest.release_channel == "v4.2.2-rc1"
      assert manifest.built_at == "2026-03-20T00:00:00Z"
      assert manifest.plugin_set == [%{name: "daisyui", version: "5.5.19"}]
      assert length(manifest.files) == 2

      macos_entry =
        Enum.find(manifest.files, fn file ->
          file.target_key == "macos-arm64"
        end)

      assert macos_entry.artifact_name == "tailwindcss-macos-arm64"
      assert macos_entry.plugin_set == [%{name: "daisyui", version: "5.5.19"}]

      assert macos_entry.storage_url ==
               "https://storage.defdo.de/tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-macos-arm64"

      assert String.length(macos_entry.checksum_sha256) == 64
    end
  end

  describe "generate_sha256_sums/1" do
    test "returns checksums in sha256sum format" do
      dir = temp_dir("deployer_checksums")
      on_exit(fn -> File.rm_rf(dir) end)

      binary = write_file(dir, "tailwindcss-linux-x64", "linux binary contents")

      deployed_files = [
        {:ok,
         %{
           local_path: binary,
           remote_key: "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
           bucket: "defdo",
           size: File.stat!(binary).size
         }}
      ]

      {:ok, sha256sums} = Deployer.generate_sha256_sums(deployed_files)

      assert sha256sums =~ "tailwindcss-linux-x64"
      assert String.match?(sha256sums, ~r/^[a-f0-9]{64}\s{2}tailwindcss-linux-x64$/m)
    end
  end

  describe "smoke_test_binary/2" do
    test "passes when the binary writes expected css output" do
      dir = temp_dir("deployer_smoke")
      on_exit(fn -> File.rm_rf(dir) end)

      script =
        write_file(
          dir,
          "tailwindcss-macos-arm64",
          """
          #!/bin/sh
          output=""
          while [ "$#" -gt 0 ]; do
            case "$1" in
              -o)
                output="$2"
                shift 2
                ;;
              *)
                shift
                ;;
            esac
          done

          printf 'html{line-height:1.5}.btn{display:inline-flex}' > "$output"
          """
        )

      File.chmod!(script, 0o755)

      assert {:ok, result} =
               Deployer.smoke_test_binary(script, expected_patterns: [".btn", "html{"])

      assert result.output_bytes > 0
    end
  end

  describe "normalize_storage_host/1" do
    test "strips https:// prefix" do
      assert Deployer.normalize_storage_host("https://example.r2.cloudflarestorage.com") ==
               "example.r2.cloudflarestorage.com"
    end

    test "strips http:// prefix" do
      assert Deployer.normalize_storage_host("http://example.r2.cloudflarestorage.com") ==
               "example.r2.cloudflarestorage.com"
    end

    test "keeps bare host unchanged" do
      assert Deployer.normalize_storage_host("example.r2.cloudflarestorage.com") ==
               "example.r2.cloudflarestorage.com"
    end

    test "strips trailing slash" do
      assert Deployer.normalize_storage_host("example.r2.cloudflarestorage.com/") ==
               "example.r2.cloudflarestorage.com"
    end

    test "strips both https:// prefix and trailing slash" do
      assert Deployer.normalize_storage_host("https://example.r2.cloudflarestorage.com/") ==
               "example.r2.cloudflarestorage.com"
    end

    test "returns nil for nil input" do
      assert Deployer.normalize_storage_host(nil) == nil
    end
  end

  describe "resolve_upload_timeout/1" do
    test "defaults to 300_000 ms when config is nil" do
      assert Deployer.resolve_upload_timeout(nil) == 300_000
    end

    test "defaults to 300_000 ms when config omits :upload_timeout" do
      assert Deployer.resolve_upload_timeout(host: "example.r2.cloudflarestorage.com") == 300_000
    end

    test "uses the configured :upload_timeout when present" do
      assert Deployer.resolve_upload_timeout(upload_timeout: 600_000) == 600_000
    end
  end

  describe "verify_uploaded_artifacts/2" do
    defp deployed_entry(dir, filename, remote_key, contents) do
      path = write_file(dir, filename, contents)

      {:ok,
       %{
         local_path: path,
         remote_key: remote_key,
         bucket: "defdo",
         size: File.stat!(path).size
       }}
    end

    defp sha256(bytes) do
      :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
    end

    test "verifies when downloaded bytes match the local checksum" do
      dir = temp_dir("deployer_verify_ok")
      on_exit(fn -> File.rm_rf(dir) end)

      contents = "linux binary contents"

      deployed_files = [
        deployed_entry(
          dir,
          "tailwindcss-linux-x64",
          "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
          contents
        )
      ]

      fetcher = fn _url -> {:ok, contents} end

      assert {:ok, report} =
               Deployer.verify_uploaded_artifacts(deployed_files,
                 storage_base_url: "https://storage.defdo.de",
                 verification_fetcher: fetcher
               )

      assert report.verified == 1
      assert report.failed == 0

      [entry] = report.results
      assert entry.status == :verified
      assert entry.artifact_name == "tailwindcss-linux-x64"

      assert entry.storage_url ==
               "https://storage.defdo.de/tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64"

      assert entry.expected_sha256 == sha256(contents)
      assert entry.actual_sha256 == entry.expected_sha256
      assert entry.error == nil
    end

    test "reports a mismatch when downloaded bytes differ" do
      dir = temp_dir("deployer_verify_mismatch")
      on_exit(fn -> File.rm_rf(dir) end)

      deployed_files = [
        deployed_entry(
          dir,
          "tailwindcss-linux-x64",
          "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
          "local bytes"
        )
      ]

      fetcher = fn _url -> {:ok, "different bytes downloaded"} end

      assert {:error, {:verification_failed, report}} =
               Deployer.verify_uploaded_artifacts(deployed_files,
                 storage_base_url: "https://storage.defdo.de",
                 verification_fetcher: fetcher
               )

      assert report.verified == 0
      assert report.failed == 1

      [entry] = report.results
      assert entry.status == :mismatch
      assert entry.actual_sha256 != nil
      assert entry.actual_sha256 != entry.expected_sha256
      assert entry.error == nil
    end

    test "reports a fetch failure with the fetcher reason" do
      dir = temp_dir("deployer_verify_fetch_error")
      on_exit(fn -> File.rm_rf(dir) end)

      deployed_files = [
        deployed_entry(
          dir,
          "tailwindcss-linux-x64",
          "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
          "local bytes"
        )
      ]

      fetcher = fn _url -> {:error, :timeout} end

      assert {:error, {:verification_failed, report}} =
               Deployer.verify_uploaded_artifacts(deployed_files,
                 storage_base_url: "https://storage.defdo.de",
                 verification_fetcher: fetcher
               )

      assert report.failed == 1

      [entry] = report.results
      assert entry.status == :fetch_failed
      assert entry.actual_sha256 == nil
      assert entry.error == :timeout
    end

    test "fails when storage_base_url is missing so no url can be built" do
      dir = temp_dir("deployer_verify_no_base")
      on_exit(fn -> File.rm_rf(dir) end)

      deployed_files = [
        deployed_entry(
          dir,
          "tailwindcss-linux-x64",
          "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
          "local bytes"
        )
      ]

      fetcher = fn _url -> {:ok, "local bytes"} end

      assert {:error, {:verification_failed, report}} =
               Deployer.verify_uploaded_artifacts(deployed_files, verification_fetcher: fetcher)

      [entry] = report.results
      assert entry.status == :fetch_failed
      assert entry.storage_url == nil
      assert match?({:missing_storage_base_url, _}, entry.error)
    end

    test "aggregates verified and failed counts across multiple artifacts" do
      dir = temp_dir("deployer_verify_mixed")
      on_exit(fn -> File.rm_rf(dir) end)

      ok_contents = "ok bytes"
      bad_contents = "bad bytes"

      deployed_files = [
        deployed_entry(
          dir,
          "tailwindcss-linux-x64",
          "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
          ok_contents
        ),
        deployed_entry(
          dir,
          "tailwindcss-macos-arm64",
          "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-macos-arm64",
          bad_contents
        )
      ]

      fetcher = fn
        _url -> {:ok, "wrong downloaded bytes"}
      end

      assert {:error, {:verification_failed, report}} =
               Deployer.verify_uploaded_artifacts(deployed_files,
                 storage_base_url: "https://storage.defdo.de",
                 verification_fetcher: fetcher
               )

      assert report.failed == 2
      assert report.verified == 0
      assert Enum.all?(report.results, &(&1.status == :mismatch))
    end

    test "returns an empty report for an empty deployed list" do
      assert {:ok, report} = Deployer.verify_uploaded_artifacts([], storage_base_url: "https://x")

      assert report == %{verified: 0, failed: 0, results: []}
    end
  end

  describe "manifest schema and provenance" do
    test "carries schema version, version split, per-artifact and provenance fields" do
      dir = temp_dir("deployer_manifest_schema")
      on_exit(fn -> File.rm_rf(dir) end)

      binary = write_file(dir, "tailwindcss-linux-x64", "linux binary contents")

      deployed_files = [
        {:ok,
         %{
           local_path: binary,
           remote_key: "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
           bucket: "defdo",
           size: File.stat!(binary).size
         }}
      ]

      {:ok, manifest} =
        Deployer.generate_deployment_manifest(
          deployed_files,
          "4.2.2",
          release_channel: "v4.2.2-rc1",
          tailwind_version: "4.2.2",
          tailwind_cli_version: "4.2.2",
          plugin_set: [%{name: "daisyui", version: "5.5.19"}],
          storage_base_url: "https://storage.defdo.de",
          built_at: "2026-03-20T00:00:00Z",
          source_checksum: "deadbeef"
        )

      assert manifest.manifest_schema_version == 1
      assert manifest.version == "4.2.2"
      assert manifest.tailwind_version == "4.2.2"
      assert manifest.tailwind_cli_version == "4.2.2"
      assert manifest.release_channel == "v4.2.2-rc1"

      [entry] = manifest.files
      assert entry.target_key == "linux-x64"
      assert entry.build_target == "x86_64-unknown-linux-gnu"
      assert entry.artifact_name == "tailwindcss-linux-x64"

      assert entry.storage_url ==
               "https://storage.defdo.de/tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64"

      assert String.length(entry.checksum_sha256) == 64
      assert is_integer(entry.size_bytes)
      assert entry.built_at == "2026-03-20T00:00:00Z"

      provenance = manifest.provenance
      assert provenance.elixir_version == System.version()
      assert provenance.arch == ArchitectureMatrix.get_host_architecture()
      assert provenance.source_checksum == "deadbeef"

      assert Map.has_key?(provenance, :os)
      assert Map.has_key?(provenance, :hostname)
      assert Map.has_key?(provenance, :node_version)
      assert Map.has_key?(provenance, :rust_version)
      assert Map.has_key?(provenance, :git_sha)
    end
  end

  describe "resolve_overwrite_plan/4" do
    @binaries [%{filename: "tailwindcss-linux-x64"}, %{filename: "tailwindcss-macos-arm64"}]

    defp policy_opts(extra) do
      [prefix: "tailwind_cli_daisyui", release_channel: "v1", storage_base_url: "https://s"] ++
        extra
    end

    test "dry_run short-circuits to :dry_run" do
      assert {:ok, :dry_run} = Deployer.resolve_overwrite_plan(@binaries, true)
    end

    test ":overwrite always uploads" do
      opts = policy_opts(overwrite_policy: :overwrite, existence_checker: fn _url -> true end)
      assert {:ok, :upload} = Deployer.resolve_overwrite_plan(@binaries, false, opts, "4.2.2")
    end

    test ":fail uploads when no artifact exists" do
      opts = policy_opts(overwrite_policy: :fail, existence_checker: fn _url -> false end)
      assert {:ok, :upload} = Deployer.resolve_overwrite_plan(@binaries, false, opts, "4.2.2")
    end

    test ":fail aborts when an artifact already exists" do
      checker = fn url -> String.contains?(url, "linux-x64") end
      opts = policy_opts(overwrite_policy: :fail, existence_checker: checker)

      assert {:error, {:artifacts_exist, ["tailwindcss-linux-x64"]}} =
               Deployer.resolve_overwrite_plan(@binaries, false, opts, "4.2.2")
    end

    test ":promote_only republishes when all artifacts exist" do
      opts = policy_opts(overwrite_policy: :promote_only, existence_checker: fn _url -> true end)
      assert {:ok, :republish} = Deployer.resolve_overwrite_plan(@binaries, false, opts, "4.2.2")
    end

    test ":promote_only aborts when an artifact is missing" do
      opts = policy_opts(overwrite_policy: :promote_only, existence_checker: fn _url -> false end)

      assert {:error, {:artifacts_missing, missing}} =
               Deployer.resolve_overwrite_plan(@binaries, false, opts, "4.2.2")

      assert "tailwindcss-linux-x64" in missing
    end

    test "reruns are deterministic under a stable policy and existence state" do
      exists = policy_opts(overwrite_policy: :fail, existence_checker: fn _url -> true end)
      run1 = Deployer.resolve_overwrite_plan(@binaries, false, exists, "4.2.2")
      run2 = Deployer.resolve_overwrite_plan(@binaries, false, exists, "4.2.2")
      assert run1 == run2
      assert {:error, {:artifacts_exist, _}} = run1

      overwrite =
        policy_opts(overwrite_policy: :overwrite, existence_checker: fn _url -> true end)

      assert Deployer.resolve_overwrite_plan(@binaries, false, overwrite, "4.2.2") ==
               Deployer.resolve_overwrite_plan(@binaries, false, overwrite, "4.2.2")
    end
  end

  describe "deploy/1 dry run" do
    setup do
      dir = temp_dir("deployer_dry_run")
      on_exit(fn -> File.rm_rf(dir) end)

      host_target_key = ArchitectureMatrix.get_host_target_key()
      artifact = Targets.artifact_name(host_target_key)

      dist =
        Path.join([dir, "tailwindcss-4.2.2", "packages", "@tailwindcss-standalone", "dist"])

      File.mkdir_p!(dist)
      File.write!(Path.join(dist, artifact), "fake binary contents")

      {:ok, dir: dir, artifact: artifact}
    end

    defp dry_run_deploy(dir) do
      Deployer.deploy(
        version: "4.2.2",
        source_path: dir,
        destination: :r2,
        dry_run: true,
        validate_binaries: false,
        smoke_test_binaries: false,
        bucket: "defdo",
        prefix: "tailwind_cli_daisyui",
        release_channel: "v4.2.2-rc1",
        storage_base_url: "https://storage.defdo.de"
      )
    end

    test "produces manifest and checksums locally without uploading", %{
      dir: dir,
      artifact: artifact
    } do
      assert {:ok, result} = dry_run_deploy(dir)

      assert result.dry_run == true
      assert result.mode == :dry_run
      assert result.binaries_deployed == 1
      assert result.auxiliary_files == []
      assert result.verification == nil

      assert result.manifest.manifest_schema_version == 1
      assert result.sha256sums =~ artifact

      [entry] = result.manifest.files
      assert entry.artifact_name == artifact

      assert entry.storage_url ==
               "https://storage.defdo.de/tailwind_cli_daisyui/v4.2.2-rc1/#{artifact}"
    end

    test "accepts merge_manifest and compose_targets opts (regression)", %{dir: dir} do
      # These opts are threaded from the release task; deploy/1 must whitelist
      # them. Dry-run skips the compose/merge network step, so this only proves
      # the option validation does not raise.
      assert {:ok, result} =
               Deployer.deploy(
                 version: "4.2.2",
                 source_path: dir,
                 destination: :r2,
                 dry_run: true,
                 validate_binaries: false,
                 smoke_test_binaries: false,
                 bucket: "defdo",
                 prefix: "tailwind_cli_daisyui_ci_canary",
                 release_channel: "v4.2.2-rc1",
                 storage_base_url: "https://storage.defdo.de",
                 merge_manifest: true,
                 compose_targets: ["linux-x64", "linux-arm64", "macos-arm64"],
                 release_fingerprint: "recipe-test"
               )

      assert result.dry_run == true
      assert result.manifest.release_fingerprint == "recipe-test"
      assert Enum.all?(result.manifest.files, &(&1.release_fingerprint == "recipe-test"))
    end

    test "is deterministic across reruns", %{dir: dir} do
      assert {:ok, run1} = dry_run_deploy(dir)
      assert {:ok, run2} = dry_run_deploy(dir)

      # Checksums are content-derived and must be byte-identical across reruns.
      assert run1.sha256sums == run2.sha256sums
      assert run1.mode == run2.mode

      # File entries match except for the wall-clock built_at timestamp.
      drop_built_at = fn files -> Enum.map(files, &Map.delete(&1, :built_at)) end
      assert drop_built_at.(run1.manifest.files) == drop_built_at.(run2.manifest.files)
    end
  end

  describe "verify_uploaded_artifacts/2 with smoke test" do
    setup do
      dir = temp_dir("deployer_verify_smoke")
      on_exit(fn -> File.rm_rf(dir) end)

      binary = write_file(dir, "tailwindcss-linux-x64", "binary bytes")

      deployed = [
        {:ok,
         %{
           local_path: binary,
           remote_key: "tailwind_cli_daisyui/v4.2.2-rc1/tailwindcss-linux-x64",
           bucket: "defdo",
           size: File.stat!(binary).size
         }}
      ]

      fetcher = fn _url -> {:ok, File.read!(binary)} end

      {:ok, deployed: deployed, fetcher: fetcher}
    end

    test "marks the artifact verified and smoke passed", %{deployed: deployed, fetcher: fetcher} do
      assert {:ok, report} =
               Deployer.verify_uploaded_artifacts(deployed,
                 storage_base_url: "https://storage.defdo.de",
                 verification_fetcher: fetcher,
                 verify_smoke_test: true,
                 verification_smoke_tester: fn _path -> {:ok, %{ok: true}} end
               )

      assert report.verified == 1
      assert report.failed == 0
      [res] = report.results
      assert res.status == :verified
      assert res.smoke_test == :passed
    end

    test "fails verification when the downloaded artifact smoke test fails", %{
      deployed: deployed,
      fetcher: fetcher
    } do
      assert {:error, {:verification_failed, report}} =
               Deployer.verify_uploaded_artifacts(deployed,
                 storage_base_url: "https://storage.defdo.de",
                 verification_fetcher: fetcher,
                 verify_smoke_test: true,
                 verification_smoke_tester: fn _path -> {:error, :empty_output} end
               )

      assert report.failed == 1
      [res] = report.results
      assert res.status == :smoke_failed
      assert res.smoke_test == :failed
    end
  end

  describe "merge_published_manifest/2" do
    # Remote (already published) manifest: only the macOS target, string keys as
    # decoded from storage JSON.
    defp remote_macos_manifest do
      %{
        "manifest_schema_version" => 1,
        "release_channel" => "v4.2.2-rc1",
        "tailwind_cli_version" => "4.2.2",
        "total_files" => 1,
        "plugin_set" => [
          %{"name" => "daisyui", "version" => "5.5.19", "plugin_key" => "daisyui_v5"}
        ],
        "files" => [
          %{
            "filename" => "tailwindcss-macos-arm64",
            "target_key" => "macos-arm64",
            "build_target" => "aarch64-apple-darwin",
            "artifact_name" => "tailwindcss-macos-arm64",
            "storage_url" => "https://storage.defdo.de/p/v4.2.2-rc1/tailwindcss-macos-arm64",
            "checksum_sha256" => "macsum",
            "size_bytes" => 77_827_552,
            "built_at" => "2026-06-28T00:19:04Z"
          }
        ]
      }
    end

    # Local (this run) manifest: only the linux-x64 target, atom keys as produced
    # by generate_deployment_manifest/3.
    defp local_linux_manifest do
      %{
        manifest_schema_version: 1,
        release_channel: "v4.2.2-rc1",
        tailwind_cli_version: "4.2.2",
        total_files: 1,
        metadata: %{plugin_set: [%{name: "daisyui", version: "5.5.19", plugin_key: "daisyui_v5"}]},
        plugin_set: [%{name: "daisyui", version: "5.5.19", plugin_key: "daisyui_v5"}],
        files: [
          %{
            filename: "tailwindcss-linux-x64",
            target_key: "linux-x64",
            build_target: "x86_64-unknown-linux-gnu",
            artifact_name: "tailwindcss-linux-x64",
            storage_url: "https://storage.defdo.de/p/v4.2.2-rc1/tailwindcss-linux-x64",
            checksum_sha256: "linsum",
            size_bytes: 1234,
            built_at: "2026-06-30T00:00:00Z"
          }
        ]
      }
    end

    test "accumulates a new target into a previously published manifest" do
      {merged, sums} =
        Deployer.merge_published_manifest(remote_macos_manifest(), local_linux_manifest())

      target_keys = merged.files |> Enum.map(& &1[:target_key]) |> Enum.sort()
      assert target_keys == ["linux-x64", "macos-arm64"]
      assert merged.total_files == 2
      # Plugin set de-duplicated by plugin_key, not doubled.
      assert length(merged.plugin_set) == 1

      # sha256sums regenerated from the merged file list, sorted, both targets.
      assert sums == "linsum  tailwindcss-linux-x64\nmacsum  tailwindcss-macos-arm64"
    end

    test "does not carry stale artifacts from another frozen recipe" do
      remote =
        remote_macos_manifest()
        |> Map.put("release_fingerprint", "recipe-old")
        |> update_in(["files"], fn files ->
          Enum.map(files, &Map.put(&1, "release_fingerprint", "recipe-old"))
        end)

      local =
        local_linux_manifest()
        |> Map.put(:release_fingerprint, "recipe-new")
        |> update_in([:files], fn files ->
          Enum.map(files, &Map.put(&1, :release_fingerprint, "recipe-new"))
        end)

      {merged, sums} = Deployer.merge_published_manifest(remote, local)

      assert Enum.map(merged.files, & &1.target_key) == ["linux-x64"]
      assert merged.release_fingerprint == "recipe-new"
      assert sums == "linsum  tailwindcss-linux-x64"
    end

    test "local entry wins on filename collision (re-publishing same target)" do
      remote = remote_macos_manifest()

      local =
        local_linux_manifest()
        |> Map.put(:files, [
          %{
            filename: "tailwindcss-macos-arm64",
            target_key: "macos-arm64",
            artifact_name: "tailwindcss-macos-arm64",
            storage_url: "https://storage.defdo.de/p/v4.2.2-rc1/tailwindcss-macos-arm64",
            checksum_sha256: "newmacsum",
            size_bytes: 999,
            built_at: "2026-06-30T00:00:00Z"
          }
        ])

      {merged, sums} = Deployer.merge_published_manifest(remote, local)

      assert merged.total_files == 1
      [file] = merged.files
      assert file[:checksum_sha256] == "newmacsum"
      assert sums == "newmacsum  tailwindcss-macos-arm64"
    end
  end

  describe "compose_manifest/2" do
    defp sibling_manifest(filename, target_key, checksum) do
      %{
        "manifest_schema_version" => 1,
        "files" => [
          %{
            "filename" => filename,
            "target_key" => target_key,
            "artifact_name" => filename,
            "storage_url" => "https://storage.defdo.de/p/v4.2.2-rc1/#{filename}",
            "checksum_sha256" => checksum,
            "size_bytes" => 100,
            "built_at" => "2026-06-30T00:00:00Z"
          }
        ]
      }
    end

    test "folds this run with sibling fragments into one multi-target manifest" do
      base = local_linux_manifest()

      siblings = [
        sibling_manifest("tailwindcss-macos-arm64", "macos-arm64", "macsum"),
        sibling_manifest("tailwindcss-linux-arm64", "linux-arm64", "armsum")
      ]

      composed = Deployer.compose_manifest(base, siblings)

      target_keys = composed.files |> Enum.map(& &1[:target_key]) |> Enum.sort()
      assert target_keys == ["linux-arm64", "linux-x64", "macos-arm64"]
      assert composed.total_files == 3
    end

    test "fold is order-independent for distinct targets" do
      base = local_linux_manifest()
      mac = sibling_manifest("tailwindcss-macos-arm64", "macos-arm64", "macsum")
      arm = sibling_manifest("tailwindcss-linux-arm64", "linux-arm64", "armsum")

      keys = fn m -> m.files |> Enum.map(& &1[:target_key]) |> Enum.sort() end

      assert keys.(Deployer.compose_manifest(base, [mac, arm])) ==
               keys.(Deployer.compose_manifest(base, [arm, mac]))
    end

    test "no siblings (others not built yet) yields just this run's target" do
      composed = Deployer.compose_manifest(local_linux_manifest(), [])
      assert composed.total_files == 1
      assert [%{target_key: "linux-x64"}] = composed.files
    end
  end
end
