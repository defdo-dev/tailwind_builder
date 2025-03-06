defmodule Defdo.TailwindBuilderTest do
  use ExUnit.Case, async: true
  import Mox
  require Logger
  alias Defdo.TailwindBuilder

  # Setup mocks for each test
  setup :verify_on_exit!

  @moduletag :capture_log
  @tailwind_version "3.4.17"
  @tailwind_v4 "4.0.9"
  @daisyui_v5 %{
    "version" => ~s["daisyui": "^5.0.0"]
  }

  @debug_build false

  @tmp_dir Path.join("/tmp", "tailwind_builder_test")

  setup_all do
    # Create a fresh directory
    File.mkdir_p!(@tmp_dir)

    # Download and build v3 if needed
    v3_path = Path.join(@tmp_dir, "tailwindcss-#{@tailwind_version}")

    if not File.exists?(v3_path) do
      {:ok, _} = TailwindBuilder.download(@tmp_dir, @tailwind_version)
      TailwindBuilder.add_plugin("daisyui", @tailwind_version, @tmp_dir)
    end

    # Download and build v4 if needed - different structure
    v4_path = Path.join(@tmp_dir, "tailwindcss-#{@tailwind_v4}")

    if not File.exists?(v4_path) do
      {:ok, _} = TailwindBuilder.download(@tmp_dir, @tailwind_v4)
      TailwindBuilder.add_plugin(@daisyui_v5, @tailwind_v4, @tmp_dir)
    end

    on_exit(fn ->
      # Clean up after all tests
      if File.exists?(@tmp_dir) and not @debug_build do
        System.cmd("rm", ["-rf", @tmp_dir])
      end
    end)

    {:ok, base_dir_v3: v3_path, base_dir_v4: v4_path}
  end

  describe "APIs low level" do
    @tag :low_level
    test "installed?/1 check is program is installed in the system" do
      assert TailwindBuilder.installed?("npm")
    end

    @tag :low_level
    test "path_for/3 retrieves the path, we expect the root path for the source code" do
      assert @tmp_dir
             |> standalone_js()
             |> File.exists?()

      assert @tmp_dir
             |> package_json()
             |> File.exists?()
    end

    @tag :low_level
    test "standalone_cli_path/2" do
      assert @tmp_dir
             |> TailwindBuilder.standalone_cli_path(@tailwind_version)
             |> TailwindBuilder.maybe_path()
             |> File.dir?()
    end
  end

  describe "Patch Content" do
    setup do
      package_json = package_json(@tmp_dir) |> File.read!()
      standalone_js = standalone_js(@tmp_dir) |> File.read!()
      index_ts = index_ts(@tmp_dir) |> File.read!()

      {:ok, package_json: package_json, standalone_js: standalone_js, index_ts: index_ts}
    end

    @tag :patch_content
    test "patch_package_json/3 invalid package json" do
      patch_string = ~s["daisyui": "^2.51.5"]

      assert {:error, :unable_to_patch} =
               TailwindBuilder.patch_package_json("invalid file", patch_string, @tailwind_version)
    end

    @tag :patch_content
    test "patch_package_json/3 patch the package.json file", %{package_json: package_json} do
      patch_string = ~s["daisyui": "^2.51.5"]

      assert TailwindBuilder.patch_package_json(package_json, patch_string, @tailwind_version) =~
               patch_string
    end

    @tag :patch_content
    test "patch_standalone_js/2 patch the standalone.js file", %{standalone_js: standalone_js} do
      patch_string = ~s['daisyui': require('daisyui')]
      assert TailwindBuilder.patch_standalone_js(standalone_js, patch_string) =~ patch_string
    end

    @tag :patch_content
    test "patch_index_ts/3 patch the standalone.js file", %{index_ts: index_ts} do
      # Test patching with daisyui
      patched_content = TailwindBuilder.patch_index_ts(index_ts, "daisyui")

      # Verify all patch points
      assert patched_content =~ "id.startsWith('daisyui') ||"
      assert patched_content =~ "if (/(\\/)?daisyui(\\/.+)?$/.test(id)) { return id }"
      assert patched_content =~ "} else if (/(\\/)?daisyui(\\/.+)?$/.test(id)) {"
      assert patched_content =~ "return require('daisyui')"
      assert patched_content =~ "'daisyui': await import('daisyui')"

      # Verify it doesn't add duplicate patches
      re_patched = TailwindBuilder.patch_index_ts(patched_content, "daisyui")
      assert re_patched == patched_content
    end
  end

  describe "APIs high level" do
    @tag :high_level
    test "add_plugin/1 injects the plugin into the source file" do
      assert ["Patch to package.json was applied.", "Patch to standalone.js was applied."] =
               TailwindBuilder.add_plugin("daisyui", @tailwind_version, @tmp_dir)
    end

    @tag :high_level
    test "Add a custom plugin" do
      custom_plugin = %{
        "version" => ~s["daisyui": "^2.51.5"],
        "statement" => ~s['daisyui': require('daisyui')]
      }

      assert ["Patch to package.json was applied.", "Patch to standalone.js was applied."] =
               TailwindBuilder.add_plugin(custom_plugin, @tailwind_version, @tmp_dir)
    end
  end

  describe "Adapters" do
    @tag :integration
    @tag timeout: 120_000
    test "download fetches tailwind source", %{base_dir_v3: base_dir} do
      assert File.dir?(base_dir)
      assert Path.basename(base_dir) == "tailwindcss-#{@tailwind_version}"
    end

    @tag :integration
    @tag :build
    @tag timeout: 300_000
    test "build tailwind v3 with daisyui v4" do
      # Step 1: Download v3 and Step 2: Add DaisyUI are at setup_all level
      # Step 3: Build
      {:ok, result} = TailwindBuilder.build(@tailwind_version, @tmp_dir)

      binary_name = get_binary_name()

      binary_path = Path.join([result.tailwind_standalone_root, "dist", binary_name])
      assert File.exists?(binary_path)

      # Step 4: Verify binary functionality
      test_css_dir = Path.join(@tmp_dir, "css_tw_v3")
      File.mkdir_p!(test_css_dir)

      # Create test input file with a DaisyUI component
      input_css = Path.join(test_css_dir, "input.css")

      File.write!(input_css, """
      @tailwind base;
      @tailwind components;
      @tailwind utilities;

      .test-btn {
        @apply btn btn-primary;
      }
      """)

      # Create test config with content paths
      config_js = Path.join(test_css_dir, "tailwind.config.js")

      File.write!(config_js, """
      module.exports = {
        content: ['#{input_css}'],
        plugins: [require('daisyui')],
        daisyui: {
          themes: ["light"],
        }
      }
      """)

      # Run the binary with --watch false to ensure full build
      output_css = Path.join(test_css_dir, "output.css")

      # Run the binary with node resolution
      opts = ["-i", input_css, "-o", output_css, "-c", config_js]

      {_output, status} = System.cmd(binary_path, opts)

      assert status == 0

      # Verify output
      assert File.exists?(output_css)
      css_content = File.read!(output_css)
      # DaisyUI color variable
      assert css_content =~ "--b1"
      # DaisyUI component
      assert css_content =~ ".btn {"
      # Custom class
      assert css_content =~ ".test-btn {"
    end

    @tag :integration
    @tag :build
    @tag timeout: 500_000
    test "build tailwind v4 with daisyui v5" do
      # Step 1: Download v3 and Step 2: Add DaisyUI are at setup_all level
      # Step 3: Build
      {:ok, result} = TailwindBuilder.build(@tailwind_v4, @tmp_dir)

      binary_name = get_binary_name()

      binary_path = Path.join([result.tailwind_standalone_root, "dist", binary_name])
      assert File.exists?(binary_path)

      # Step 4: Verify binary functionality
      test_css_dir = Path.join(@tmp_dir, "css_tw_v4")
      File.mkdir_p!(test_css_dir)

      # Create test input file with DaisyUI v5 components
      input_css = Path.join(test_css_dir, "input.css")

      File.write!(input_css, """
      @import "tailwindcss";
      @plugin "daisyui";

      .test-btn {
        @apply btn btn-primary;
      }
      """)

      # Run the binary
      output_css = Path.join(test_css_dir, "output.css")

      opts = ["-i", input_css, "-o", output_css]

      {_output, status} = System.cmd(binary_path, opts)

      assert status == 0

      # Verify output
      assert File.exists?(output_css)
      css_content = File.read!(output_css)
      # DaisyUI color variable
      assert css_content =~ "--color-base-100"
      # DaisyUI component
      assert css_content =~ ".btn {"
      # Custom class
      assert css_content =~ ".test-btn {"
    end

    @tag :integration
    @tag :deploy_r2
    test "deploy uploads built artifacts to R2" do
      test_bucket = "test-bucket"
      version_path = "tailwind_cli_daisyui/v#{@tailwind_v4}/"

      # Mock with different responses for each S3 operation
      Mox.stub(ExAws.Request.HttpMock, :request, fn
        # List operation
        :get, _url, _body, _headers, _opts ->
          {:ok,
           %{
             status_code: 200,
             body: """
             <?xml version="1.0" encoding="UTF-8"?>
             <ListBucketResult>
               <Contents>
                 <Key>#{version_path}tailwindcss-macos-arm64</Key>
               </Contents>
             </ListBucketResult>
             """
           }}

        # Upload part operation
        :put, url, _body, _headers, _opts ->
          if String.contains?(url, "partNumber=") do
            {:ok,
             %{
               status_code: 200,
               headers: [{"ETag", "\"test-etag\""}],
               body: ""
             }}
          else
            {:ok, %{status_code: 200, body: ""}}
          end

        # Complete multipart upload
        :post, url, _body, _headers, _opts ->
          cond do
            String.contains?(url, "uploadId=") ->
              {:ok,
               %{
                 status_code: 200,
                 body: """
                 <?xml version="1.0" encoding="UTF-8"?>
                 <CompleteMultipartUploadResult>
                   <Location>https://#{test_bucket}.cloudflareaccess.com/#{version_path}</Location>
                   <Bucket>#{test_bucket}</Bucket>
                   <Key>#{version_path}</Key>
                   <ETag>"test-etag"</ETag>
                 </CompleteMultipartUploadResult>
                 """
               }}

            true ->
              {:ok,
               %{
                 status_code: 200,
                 body: """
                 <?xml version="1.0" encoding="UTF-8"?>
                 <InitiateMultipartUploadResult>
                   <Bucket>#{test_bucket}</Bucket>
                   <Key>#{version_path}</Key>
                   <UploadId>test-upload-id</UploadId>
                 </InitiateMultipartUploadResult>
                 """
               }}
          end

        # Default response for any other request
        _method, _url, _body, _headers, _opts ->
          {:ok, %{status_code: 200, body: ""}}
      end)

      # {:ok, _result} = TailwindBuilder.build(@tailwind_v4, @tmp_dir)

      # Configure ExAws for testing
      Application.put_env(:ex_aws, :access_key_id, "test_key")
      Application.put_env(:ex_aws, :secret_access_key, "test_secret")
      Application.put_env(:ex_aws, :region, "auto")
      Application.put_env(:ex_aws, :s3, host: "test.cloudflareaccess.com")

      assert [record | _] =
               response = TailwindBuilder.deploy_r2(@tailwind_v4, @tmp_dir, test_bucket)

      assert length(response)
      assert is_map_key(record, :body)
      # Verify that our mock was called
      Mox.verify!()
    end
  end

  defp package_json(tailwind_src) do
    path =
      Path.join([
        tailwind_src,
        "tailwindcss-#{@tailwind_version}",
        "standalone-cli",
        "package.json"
      ])

    if not File.exists?(path),
      do: raise("Tailwind source files not found. Ensure setup_all downloaded the files.")

    path
  end

  defp standalone_js(tailwind_src) do
    path =
      Path.join([
        tailwind_src,
        "tailwindcss-#{@tailwind_version}",
        "standalone-cli",
        "standalone.js"
      ])

    if not File.exists?(path),
      do: raise("Tailwind source files not found. Ensure setup_all downloaded the files.")

    path
  end

  defp index_ts(tailwind_src) do
    path =
      Path.join([
        tailwind_src,
        "tailwindcss-#{@tailwind_v4}",
        "packages/@tailwindcss-standalone/src",
        "index.ts"
      ])

    if not File.exists?(path),
      do: raise("Tailwind source files not found. Ensure setup_all downloaded the files.")

    path
  end

  defp get_binary_name do
    case :os.type() do
      {:unix, :darwin} ->
        arch =
          if "#{:erlang.system_info(:system_architecture)}" =~ "aarch64" do
            "arm64"
          else
            "x64"
          end

        "tailwindcss-macos-#{arch}"

      {:unix, _} ->
        "tailwindcss-linux-x64"

      {:win32, _} ->
        "tailwindcss-windows-x64.exe"
    end
  end
end
