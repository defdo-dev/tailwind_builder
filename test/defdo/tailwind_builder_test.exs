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
    "version" => ~s["daisyui": "^5.0.0"],
    "statement" => ~s['daisyui': require('daisyui')]
  }

  # System.tmp_dir!()
  @tmp_dir Path.join("/tmp", "tailwind_builder_test")

  setup_all do
    # Create tmp directory for tests
    File.mkdir_p!(@tmp_dir)

    # Download and build v3 if needed
    v3_path = Path.join(@tmp_dir, "tailwindcss-#{@tailwind_version}")

    if not File.exists?(v3_path) do
      {:ok, _} = TailwindBuilder.download(@tmp_dir, @tailwind_version)
      TailwindBuilder.add_plugin("daisyui", @tailwind_version, @tmp_dir)
      TailwindBuilder.build(@tmp_dir, @tailwind_version)
    end

    # Download and build v4 if needed - different structure
    v4_path = Path.join(@tmp_dir, "tailwindcss-#{@tailwind_v4}")

    if not File.exists?(v4_path) do
      {:ok, _} = TailwindBuilder.download(@tmp_dir, @tailwind_v4)
      # Install dependencies before building
      {_, 0} = System.cmd("pnpm", ["install"], cd: v4_path)

      TailwindBuilder.add_plugin(@daisyui_v5, @tailwind_v4, @tmp_dir)
      TailwindBuilder.build(@tmp_dir, @tailwind_v4)
    end

    {:ok, base_dir_v3: v3_path, base_dir_v4: v4_path}
  end

  # Helper to get binary path based on version
  defp get_binary_path(base_dir, version \\ @tailwind_version) do
    binary_name =
      case :os.type() do
        {:unix, :darwin} -> "tailwindcss-macos-#{System.get_env("HOSTTYPE", "arm64")}"
        {:unix, _} -> "tailwindcss-linux-x64"
        {:win32, _} -> "tailwindcss-windows-x64.exe"
      end

    # V4 has a different output structure
    if version == @tailwind_v4 do
      Path.join([base_dir, "standalone-cli", "dist", binary_name])
    else
      Path.join([base_dir, "standalone-cli/dist", binary_name])
    end
  end

  describe "APIs low level" do
    @tag :low_level
    test "is_installed?/1 check is program is installed in the system" do
      assert TailwindBuilder.is_installed?("npm")
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

      {:ok, package_json: package_json, standalone_js: standalone_js}
    end

    @tag :patch_content
    test "patch_package_json/2 invalid package json" do
      patch_string = ~s["daisyui": "^2.51.5"]

      assert {:error, :unable_to_patch} =
               TailwindBuilder.patch_package_json("invalid file", patch_string)
    end

    @tag :patch_content
    test "patch_package_json/2 patch the package.json file", %{package_json: package_json} do
      patch_string = ~s["daisyui": "^2.51.5"]
      assert TailwindBuilder.patch_package_json(package_json, patch_string) =~ patch_string
    end

    @tag :patch_content
    test "patch_standalone_js/2 patch the standalone.js file", %{standalone_js: standalone_js} do
      patch_string = ~s['daisyui': require('daisyui')]
      assert TailwindBuilder.patch_standalone_js(standalone_js, patch_string) =~ patch_string
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
    test "download fetches tailwind source", %{base_dir: base_dir} do
      assert File.dir?(base_dir)
      assert Path.basename(base_dir) == "tailwindcss-#{@tailwind_version}"
    end

    @tag :integration
    @tag :build
    @tag timeout: 300_000
    test "full integration tailwind v3 with daisyui v4 flow: plugin -> build -> verify", %{
      base_dir_v3: base_dir
    } do
      # Step 1: Add Plugin (using existing downloaded source)
      assert ["Patch to package.json was applied.", "Patch to standalone.js was applied."] =
               TailwindBuilder.add_plugin("daisyui", @tailwind_version, @tmp_dir)

      # Rest of the test remains the same...
      test_dir = Path.join(@tmp_dir, "integration_test")
      File.rm_rf!(test_dir)
      File.mkdir_p!(test_dir)

      # Step 1: Download
      {:ok, _} = TailwindBuilder.download(test_dir, @tailwind_version)

      # Step 2: Add Plugin
      assert ["Patch to package.json was applied.", "Patch to standalone.js was applied."] =
               TailwindBuilder.add_plugin("daisyui", @tailwind_version, test_dir)

      # Step 3: Build
      {:ok, result} = TailwindBuilder.build(test_dir, @tailwind_version)

      binary_name =
        case :os.type() do
          {:unix, :darwin} -> "tailwindcss-macos-#{System.get_env("HOSTTYPE", "x64")}"
          {:unix, _} -> "tailwindcss-linux-x64"
          {:win32, _} -> "tailwindcss-windows-x64.exe"
        end

      binary_path = Path.join([result.tailwind_standalone_root, "dist", binary_name])
      assert File.exists?(binary_path)

      # Step 4: Verify binary functionality
      test_css_dir = Path.join(test_dir, "css_test")
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
      node_modules = Path.join(test_css_dir, "node_modules")
      File.mkdir_p!(node_modules)

      # Install daisyui locally for the test
      {_, 0} = System.cmd("npm", ["init", "-y"], cd: test_css_dir)
      {_, 0} = System.cmd("npm", ["install", "daisyui@latest"], cd: test_css_dir)

      # Run the binary with node resolution
      {output, status} =
        System.cmd(
          binary_path,
          [
            "-i",
            input_css,
            "-o",
            output_css,
            "-c",
            config_js,
            "--watch",
            "false",
            "--minify",
            "false"
          ],
          cd: test_css_dir
        )

      Logger.debug("Binary output: #{output}")
      assert status == 0

      # Verify output
      assert File.exists?(output_css)
      css_content = File.read!(output_css)
      assert css_content =~ "daisyui"
      # DaisyUI component
      assert css_content =~ ".btn"
    end

    @tag :integration
    @tag :build
    @tag timeout: 300_000
    @tag :focus
    test "build tailwind v4 with daisyui v5", %{base_dir_v4: base_dir} do
      # Step 1: Download v4
      test_dir = Path.join(@tmp_dir, "integration_test_v4")
      File.rm_rf!(test_dir)
      File.mkdir_p!(test_dir)

      {:ok, _} = TailwindBuilder.download(test_dir, @tailwind_v4)

      # Step 2: Add DaisyUI v5
      assert ["Patch to package.json was applied."] =
               TailwindBuilder.add_plugin(@daisyui_v5, @tailwind_v4, test_dir)

      # Step 3: Build (should handle all installations)
      {:ok, result} = TailwindBuilder.build(test_dir, @tailwind_v4)

      # Now check if binary exists after build
      binary_path = get_binary_path(base_dir, @tailwind_v4)
      assert File.exists?(binary_path)

      # Rest of test remains the same...
      binary_name =
        case :os.type() do
          {:unix, :darwin} -> "tailwindcss-macos-#{System.get_env("HOSTTYPE", "x64")}"
          {:unix, _} -> "tailwindcss-linux-x64"
          {:win32, _} -> "tailwindcss-windows-x64.exe"
        end

      binary_path = Path.join([result.tailwind_standalone_root, "dist", binary_name])
      assert File.exists?(binary_path)

      # Step 4: Verify binary functionality
      test_css_dir = Path.join(test_dir, "css_test")
      File.mkdir_p!(test_css_dir)

      # Create test input file with DaisyUI v5 components
      input_css = Path.join(test_css_dir, "input.css")

      File.write!(input_css, """
      @tailwind base;
      @tailwind components;
      @tailwind utilities;

      .test-btn {
        @apply btn btn-primary;
      }
      """)

      # Create test config with DaisyUI v5 config
      config_js = Path.join(test_css_dir, "tailwind.config.js")

      File.write!(config_js, """
      module.exports = {
        content: ['#{input_css}'],
        plugins: [require('daisyui')],
        daisyui: {
          themes: ["light"],
          logs: false
        }
      }
      """)

      # Run the binary
      output_css = Path.join(test_css_dir, "output.css")

      {_output, 0} =
        System.cmd(binary_path, [
          "-i",
          input_css,
          "-o",
          output_css,
          "-c",
          config_js,
          "--watch",
          "false",
          "--minify",
          "false"
        ])

      # Verify output
      assert File.exists?(output_css)
      css_content = File.read!(output_css)
      assert css_content =~ "daisyui"
      # DaisyUI v5 component
      assert css_content =~ ".btn"
    end

    @tag :integration
    @tag :deploy
    test "deploy uploads built artifacts to R2" do
      test_bucket = "test-bucket"
      version_path = "tailwind_cli_daisyui/v#{@tailwind_version}/"

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

      # Configure ExAws for testing
      Application.put_env(:ex_aws, :access_key_id, "test_key")
      Application.put_env(:ex_aws, :secret_access_key, "test_secret")
      Application.put_env(:ex_aws, :region, "auto")
      Application.put_env(:ex_aws, :s3, host: "test.cloudflareaccess.com")

      assert [record | _] =
               response = TailwindBuilder.deploy_s3(@tmp_dir, @tailwind_version, test_bucket)

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
end
