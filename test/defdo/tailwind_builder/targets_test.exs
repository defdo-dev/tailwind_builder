defmodule Defdo.TailwindBuilder.TargetsTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Core

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
