defmodule Defdo.TailwindBuilderTest do
   use ExUnit.Case, async: true
  alias Defdo.TailwindBuilder
  @tailwind_version "3.3.0"

  describe "APIs low level" do
    test "is_installed?/1 check is program is installed in the system" do
      assert TailwindBuilder.is_installed?("npm")
    end

    test "path_for/3 retrieves the path, we expect the root path for the source code" do
      tailwind_src = File.cwd!()

      assert tailwind_src
             |> standalone_js()
             |> File.exists?()

      assert tailwind_src
             |> package_json()
             |> File.exists?()
    end

    test "standalone_cli_path/2" do
      tailwind_src = File.cwd!()

      assert tailwind_src
             |> TailwindBuilder.standalone_cli_path(@tailwind_version)
             |> TailwindBuilder.maybe_path()
             |> File.dir?()
    end
  end

  describe "Patch Content" do
    setup do
      tailwind_src = File.cwd!()
      package_json = package_json(tailwind_src) |> File.read!()
      standalone_js = standalone_js(tailwind_src) |> File.read!()

      {:ok, package_json: package_json, standalone_js: standalone_js}
    end

    test "patch_package_json/2 invalid package json" do
      patch_string = ~s["daisyui": "^2.51.5"]

      assert {:error, :unable_to_patch} =
               TailwindBuilder.patch_package_json("invalid file", patch_string)
    end

    test "patch_package_json/2 patch the package.json file", %{package_json: package_json} do
      patch_string = ~s["daisyui": "^2.51.5"]
      assert TailwindBuilder.patch_package_json(package_json, patch_string) =~ patch_string
    end

    test "patch_standalone_js/2 patch the standalone.js file", %{standalone_js: standalone_js} do
      patch_string = ~s['daisyui': require('daisyui')]
      assert TailwindBuilder.patch_standalone_js(standalone_js, patch_string) =~ patch_string
    end
  end

  describe "APIs high level" do
    test "add_plugin/1 injects the plugin into the source file" do
      assert ["Patch to package.json was applied.", "Patch to standalone.js was applied."] =
               TailwindBuilder.add_plugin("daisyui")
    end

    test "Add a custom plugin" do
      custom_plugin = %{
        "version" => ~s["daisyui": "^2.51.5"],
        "statement" => ~s['daisyui': require('daisyui')]
      }

      assert ["Patch to package.json was applied.", "Patch to standalone.js was applied."] =
               TailwindBuilder.add_plugin(custom_plugin)
    end
  end

  describe "Adapters" do
    @tag :skip
    test "build" do
      # {"\n> tailwindcss-standalone@0.0.0 prebuild\n> rimraf dist\n\n\n> tailwindcss-standalone@0.0.0 build\n> pkg . --compress Brotli --no-bytecode --public-packages \"*\" --public\n\n> pkg@5.8.0\ncompression:  Brotli\n> Warning Cannot find module 'tailwindcss/lib/cli' from '/Volumes/data/defdo_cloud/Devel/defdo/defdo_apps/experiments_ui/build_tw_cli/tailwindcss-3.2.4/standalone-cli'  in /Volumes/data/defdo_cloud/Devel/defdo/defdo_apps/experiments_ui/build_tw_cli/tailwindcss-3.2.4/standalone-cli/standalone.js\n> Warning Cannot find module 'tailwindcss' from '/Volumes/data/defdo_cloud/Devel/defdo/defdo_apps/experiments_ui/build_tw_cli/tailwindcss-3.2.4/standalone-cli'  in /Volumes/data/defdo_cloud/Devel/defdo/defdo_apps/experiments_ui/build_tw_cli/tailwindcss-3.2.4/standalone-cli/standalone.js\n\n> tailwindcss-standalone@0.0.0 postbuild\n> move-file dist/tailwindcss-standalone-macos-x64 dist/tailwindcss-macos-x64 && move-file dist/tailwindcss-standalone-macos-arm64 dist/tailwindcss-macos-arm64 && move-file dist/tailwindcss-standalone-win-x64.exe dist/tailwindcss-windows-x64.exe && move-file dist/tailwindcss-standalone-linuxstatic-x64 dist/tailwindcss-linux-x64 && move-file dist/tailwindcss-standalone-linuxstatic-arm64 dist/tailwindcss-linux-arm64 && move-file dist/tailwindcss-standalone-linuxstatic-armv7 dist/tailwindcss-linux-armv7\n\n", 0}

      assert {stream, 0} = TailwindBuilder.build()
      assert stream =~ "move-file"
    end

    @tag :skip
    test "deploy" do
      assert 1 == 1
    end

    @tag :skip
    test "download" do
      assert 1 == 1
    end
  end

  defp package_json(tailwind_src) do
    tailwind_src
    |> TailwindBuilder.path_for(@tailwind_version, "package.json")
  end

  defp standalone_js(tailwind_src) do
    tailwind_src
    |> TailwindBuilder.path_for(@tailwind_version, "standalone.js")
  end
end
