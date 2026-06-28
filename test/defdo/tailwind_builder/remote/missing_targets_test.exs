defmodule Defdo.TailwindBuilder.Remote.MissingTargetsTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Remote.MissingTargets

  describe "report/1" do
    test "returns empty buckets when all desired targets are published" do
      result =
        MissingTargets.report(
          desired: ["linux-x64", "macos-arm64"],
          published: ["linux-x64", "macos-arm64"],
          buildable: [],
          failed: []
        )

      assert result.published == ["linux-x64", "macos-arm64"]
      assert result.buildable_now == []
      assert result.missing == []
      assert result.failed == []
    end

    test "puts unpublished but buildable targets in buildable_now" do
      result =
        MissingTargets.report(
          desired: ["linux-x64", "linux-arm64"],
          published: ["linux-x64"],
          buildable: ["linux-arm64"],
          failed: []
        )

      assert result.published == ["linux-x64"]
      assert result.buildable_now == ["linux-arm64"]
      assert result.missing == []
    end

    test "puts unreachable targets in missing" do
      result =
        MissingTargets.report(
          desired: ["linux-x64", "linux-arm64", "macos-arm64"],
          published: ["linux-x64"],
          buildable: [],
          failed: []
        )

      assert result.published == ["linux-x64"]
      assert result.buildable_now == []
      assert result.missing == ["linux-arm64", "macos-arm64"]
    end

    test "puts failed targets in failed bucket" do
      result =
        MissingTargets.report(
          desired: ["linux-x64", "macos-arm64"],
          published: [],
          buildable: ["linux-x64"],
          failed: ["macos-arm64"]
        )

      assert result.buildable_now == ["linux-x64"]
      assert result.failed == ["macos-arm64"]
      assert result.missing == []
    end

    test "normalizes build_target aliases to canonical target_key" do
      # Accepts any alias known to Targets
      result =
        MissingTargets.report(
          desired: ["x86_64-unknown-linux-gnu"],
          published: ["linux-x64"],
          buildable: [],
          failed: []
        )

      assert result.published == ["linux-x64"]
    end

    test "accepts map input" do
      result =
        MissingTargets.report(%{
          desired: ["linux-x64"],
          published: ["linux-x64"],
          buildable: [],
          failed: []
        })

      assert result.published == ["linux-x64"]
    end

    test "returns all desired as missing when no info provided" do
      result = MissingTargets.report(desired: ["linux-x64", "macos-arm64"])
      assert "linux-x64" in result.missing
      assert "macos-arm64" in result.missing
    end

    test "returns empty report with empty desired list" do
      result = MissingTargets.report(desired: [])
      assert result == %{published: [], buildable_now: [], missing: [], failed: []}
    end

    test "unknown aliases are kept as-is and land in missing" do
      result = MissingTargets.report(desired: ["amiga-68k"], published: [])
      assert "amiga-68k" in result.missing
    end
  end

  describe "published_from_manifest/1" do
    test "extracts target_keys from files list" do
      manifest = %{
        "files" => [
          %{"target_key" => "macos-arm64", "artifact_name" => "tailwindcss-macos-arm64"},
          %{"target_key" => "linux-x64", "artifact_name" => "tailwindcss-linux-x64"}
        ]
      }

      result = MissingTargets.published_from_manifest(manifest)
      assert "macos-arm64" in result
      assert "linux-x64" in result
    end

    test "works with atom :artifacts key (validated manifest)" do
      manifest = %{
        artifacts: [
          %{target_key: "macos-arm64"},
          %{target_key: "linux-x64"}
        ]
      }

      result = MissingTargets.published_from_manifest(manifest)
      assert "macos-arm64" in result
    end

    test "returns empty list for empty manifest" do
      assert MissingTargets.published_from_manifest(%{}) == []
    end
  end

  describe "all_canonical_targets/0" do
    test "includes the expected set of canonical target keys" do
      targets = MissingTargets.all_canonical_targets()
      assert "linux-x64" in targets
      assert "linux-arm64" in targets
      assert "linux-arm" in targets
      assert "macos-x64" in targets
      assert "macos-arm64" in targets
      assert "windows-x64" in targets
    end
  end
end
