defmodule Defdo.TailwindBuilder.TargetsTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Core
  alias Defdo.TailwindBuilder.Core.Targets

  describe "target normalization" do
    test "normalizes legacy darwin aliases to canonical macos keys" do
      assert Core.canonical_target_key("darwin-arm64") == "macos-arm64"
      assert Core.canonical_target_key("darwin-x64") == "macos-x64"
    end

    test "resolves preferred build targets and artifact names" do
      assert Core.build_target("macos-arm64") == "aarch64-apple-darwin"
      assert Core.build_target("linux-x64") == "x86_64-unknown-linux-gnu"
      assert Core.artifact_name_for_target("darwin-arm64") == "tailwindcss-macos-arm64"
      assert Core.artifact_name_for_target("win32-x64") == "tailwindcss-windows-x64.exe"
    end

    test "matches canonical, legacy, and build-target identifiers" do
      assert Core.targets_match?("macos-arm64", "darwin-arm64")
      assert Core.targets_match?("macos-arm64", "aarch64-apple-darwin")
      assert Core.targets_match?("linux-x64", "x86_64-unknown-linux-gnu")
      refute Core.targets_match?("linux-arm64", "x86_64-unknown-linux-gnu")
    end
  end

  describe "musl targets" do
    test "normalize as first-class optional targets, not gnu aliases" do
      assert {:ok, x64} = Targets.normalize("linux-x64-musl")
      assert x64.target_key == "linux-x64-musl"
      assert x64.build_target == "x86_64-unknown-linux-musl"
      assert x64.artifact_name == "tailwindcss-linux-x64-musl"
      assert x64.tier == :optional

      assert {:ok, arm64} = Targets.normalize("aarch64-unknown-linux-musl")
      assert arm64.target_key == "linux-arm64-musl"
      assert arm64.artifact_name == "tailwindcss-linux-arm64-musl"
    end

    test "gnu and musl keys are distinct targets" do
      refute Targets.matches?("linux-x64", "linux-x64-musl")
      assert Targets.canonical_target_key("linux-x64") == "linux-x64"
      assert Targets.canonical_target_key("tailwindcss-linux-x64-musl" |> Targets.target_key_from_filename()) ==
               "linux-x64-musl"
    end

    test "musl_sibling maps gnu linux hosts only" do
      assert Targets.musl_sibling("linux-x64") == "linux-x64-musl"
      assert Targets.musl_sibling("linux-arm64") == "linux-arm64-musl"
      assert Targets.musl_sibling("macos-arm64") == nil
      assert Targets.musl_sibling("windows-x64") == nil
    end

    test "musl keys appear as optional target keys" do
      assert "linux-x64-musl" in Targets.optional_target_keys()
      assert "linux-arm64-musl" in Targets.optional_target_keys()
      refute "linux-x64-musl" in Targets.required_target_keys()
    end
  end

  describe "available target keys" do
    test "returns canonical target keys for v4 architectures" do
      target_keys = Core.get_available_target_keys("4.1.11")

      assert "linux-x64" in target_keys
      assert "linux-arm64" in target_keys
      assert "macos-arm64" in target_keys
      assert "windows-x64" in target_keys
    end
  end
end
