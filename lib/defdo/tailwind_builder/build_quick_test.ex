defmodule Defdo.TailwindBuilder.BuildQuickTest do
  @moduledoc """
  Quick testing scenarios for TailwindCSS builds with visual progress monitoring.

  Provides pre-configured test scenarios for common build configurations
  with real-time progress updates and failure detection.

  ## Usage

      # Test basic v4 build with DaisyUI
      BuildQuickTest.run(:v4_basic, "/tmp/test_dir")

      # Test with custom theme
      BuildQuickTest.run(:v4_with_theme, "/tmp/test_dir")

      # Test with progress monitoring
      BuildQuickTest.run_with_monitoring(:v4_basic, "/tmp/test_dir", self())

  ## Test Scenarios

  - `:v4_basic` - Tailwind v4.1.14 with DaisyUI v5.1.27
  - `:v4_with_theme` - Tailwind v4.1.14 with DaisyUI and custom theme
  - `:v3_legacy` - Tailwind v3.4.17 with DaisyUI v4.12
  - `:cross_platform` - Test cross-compilation capabilities
  """

  alias Defdo.TailwindBuilder
  alias Defdo.TailwindBuilder.BuildMonitor
  require Logger

  @test_scenarios %{
    v4_basic: %{
      version: "4.1.14",
      plugin: %{"version" => ~s["daisyui": "^5.1.27"]},
      description: "Basic Tailwind v4 with DaisyUI v5",
      expected_duration_ms: 90_000,
      test_css: "@import \"tailwindcss\"; @plugin \"daisyui\";"
    },
    v4_with_theme: %{
      version: "4.1.14",
      plugin: %{"version" => ~s["daisyui": "^5.1.27"]},
      theme: %{
        "mytheme" => %{
          "primary" => "#570df8",
          "secondary" => "#f000b8",
          "accent" => "#37cdbe",
          "neutral" => "#3d4451",
          "base-100" => "#ffffff"
        }
      },
      description: "Tailwind v4 with DaisyUI and custom theme",
      expected_duration_ms: 95_000,
      test_css:
        "@import \"tailwindcss\"; @plugin \"daisyui\"; @config { theme: { extend: { colors: { mytheme: \"#570df8\" } } } };"
    },
    v3_legacy: %{
      version: "3.4.17",
      plugin: %{
        "version" => ~s["daisyui": "^4.12.23"],
        "statement" => ~s['daisyui': require('daisyui')]
      },
      description: "Legacy Tailwind v3 with DaisyUI v4",
      expected_duration_ms: 120_000,
      test_css: "@tailwind base; @tailwind components; @tailwind utilities;"
    },
    cross_platform: %{
      version: "4.1.14",
      plugin: %{"version" => ~s["daisyui": "^5.1.27"]},
      target_arch: "linux-x64",
      description: "Cross-platform build test (macOS → Linux)",
      expected_duration_ms: 100_000,
      test_css: "@import \"tailwindcss\"; @plugin \"daisyui\";"
    }
  }

  @doc """
  Run a quick test scenario without monitoring
  """
  def run(scenario_name, working_dir) when is_atom(scenario_name) do
    case Map.get(@test_scenarios, scenario_name) do
      nil ->
        {:error, {:unknown_scenario, scenario_name, available_scenarios()}}

      scenario ->
        execute_scenario(scenario, working_dir, nil)
    end
  end

  @doc """
  Run a quick test scenario with real-time monitoring
  """
  def run_with_monitoring(scenario_name, working_dir, subscriber_pid)
      when is_atom(scenario_name) and is_pid(subscriber_pid) do
    case Map.get(@test_scenarios, scenario_name) do
      nil ->
        {:error, {:unknown_scenario, scenario_name, available_scenarios()}}

      scenario ->
        {:ok, monitor_pid} = BuildMonitor.start_monitoring(subscriber_pid)
        result = execute_scenario(scenario, working_dir, monitor_pid)
        BuildMonitor.stop_monitoring(monitor_pid)
        result
    end
  end

  @doc """
  List all available test scenarios
  """
  def available_scenarios do
    Map.keys(@test_scenarios)
  end

  @doc """
  Get details about a specific scenario
  """
  def scenario_details(scenario_name) when is_atom(scenario_name) do
    Map.get(@test_scenarios, scenario_name)
  end

  @doc """
  Run all scenarios in sequence (useful for regression testing)
  """
  def run_all_scenarios(working_dir, subscriber_pid \\ nil) do
    results =
      for {scenario_name, _scenario} <- @test_scenarios do
        Logger.info("Running scenario: #{scenario_name}")

        result =
          case subscriber_pid do
            nil ->
              run(scenario_name, Path.join(working_dir, to_string(scenario_name)))

            pid ->
              run_with_monitoring(
                scenario_name,
                Path.join(working_dir, to_string(scenario_name)),
                pid
              )
          end

        {scenario_name, result}
      end

    summary = %{
      total: length(results),
      passed: Enum.count(results, fn {_name, result} -> match?({:ok, _}, result) end),
      failed: Enum.count(results, fn {_name, result} -> match?({:error, _}, result) end),
      results: results
    }

    Logger.info("Test summary: #{summary.passed}/#{summary.total} passed")
    {:ok, summary}
  end

  ## Private Functions

  defp execute_scenario(scenario, working_dir, monitor_pid) do
    scenario_dir = ensure_clean_directory(working_dir)
    start_time = System.monotonic_time()

    Logger.info("🧪 Starting test: #{scenario.description}")
    if monitor_pid, do: send_test_update(monitor_pid, :test_start, scenario)

    try do
      # Step 1: Download
      Logger.info("📥 Downloading Tailwind v#{scenario.version}...")
      if monitor_pid, do: send_test_update(monitor_pid, :download_start, scenario)

      {:ok, _} = TailwindBuilder.download(scenario_dir, scenario.version)

      if monitor_pid, do: send_test_update(monitor_pid, :download_complete, scenario)

      # Step 2: Add Plugin
      Logger.info("🔌 Adding plugin...")
      if monitor_pid, do: send_test_update(monitor_pid, :plugin_start, scenario)

      TailwindBuilder.add_plugin(scenario.plugin, scenario.version, scenario_dir)

      if monitor_pid, do: send_test_update(monitor_pid, :plugin_complete, scenario)

      # Step 3: Build
      Logger.info("🏗️  Building binary...")
      if monitor_pid, do: send_test_update(monitor_pid, :build_start, scenario)

      # Note: target_arch support could be added here in the future if needed
      # _build_options = case Map.get(scenario, :target_arch) do
      #   nil -> []
      #   arch -> [target_arch: arch]
      # end

      {:ok, build_result} = TailwindBuilder.build(scenario.version, scenario_dir, false)

      if monitor_pid, do: send_test_update(monitor_pid, :build_complete, scenario)

      # Step 4: Test Binary
      Logger.info("🧪 Testing binary functionality...")
      if monitor_pid, do: send_test_update(monitor_pid, :test_binary_start, scenario)

      test_result = test_binary_functionality(build_result, scenario)

      if monitor_pid, do: send_test_update(monitor_pid, :test_binary_complete, scenario)

      duration_ms =
        System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

      result = %{
        scenario: scenario.description,
        version: scenario.version,
        duration_ms: duration_ms,
        expected_duration_ms: scenario.expected_duration_ms,
        performance_ratio: duration_ms / scenario.expected_duration_ms,
        build_result: build_result,
        test_result: test_result,
        working_dir: scenario_dir
      }

      Logger.info(
        "✅ Test completed in #{duration_ms}ms (expected: #{scenario.expected_duration_ms}ms)"
      )

      if monitor_pid,
        do: send_test_update(monitor_pid, :test_success, %{scenario | result: result})

      {:ok, result}
    rescue
      error ->
        duration_ms =
          System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

        Logger.error("❌ Test failed after #{duration_ms}ms: #{inspect(error)}")
        if monitor_pid, do: send_test_update(monitor_pid, :test_error, %{scenario | error: error})
        {:error, {error, __STACKTRACE__}}
    end
  end

  defp ensure_clean_directory(working_dir) do
    if File.exists?(working_dir) do
      File.rm_rf!(working_dir)
    end

    File.mkdir_p!(working_dir)
    working_dir
  end

  defp test_binary_functionality(build_result, scenario) do
    binary_path = find_binary_path(build_result)

    case binary_path do
      nil ->
        {:error, :binary_not_found}

      path when is_binary(path) ->
        # Test 1: Help command
        case System.cmd(path, ["--help"], stderr_to_stdout: true) do
          {output, 0} when is_binary(output) ->
            if String.contains?(output, "tailwindcss") do
              # Test 2: CSS compilation
              test_css_compilation(path, scenario)
            else
              {:error, :invalid_help_output}
            end

          {error_output, exit_code} ->
            {:error, {:help_command_failed, exit_code, error_output}}
        end
    end
  end

  defp test_css_compilation(binary_path, scenario) do
    temp_dir = System.tmp_dir!()
    input_file = Path.join(temp_dir, "test-input.css")
    output_file = Path.join(temp_dir, "test-output.css")

    try do
      File.write!(input_file, scenario.test_css)

      case System.cmd(binary_path, ["--input", input_file, "--output", output_file],
             stderr_to_stdout: true,
             cd: temp_dir
           ) do
        {output, 0} ->
          if File.exists?(output_file) do
            css_content = File.read!(output_file)

            if String.contains?(css_content, "tailwindcss") do
              {:ok,
               %{
                 output: output,
                 css_size: byte_size(css_content),
                 has_daisyui:
                   String.contains?(css_content, "daisyUI") or String.contains?(output, "daisyUI")
               }}
            else
              {:error, :invalid_css_output}
            end
          else
            {:error, :output_file_not_created}
          end

        {error_output, exit_code} ->
          {:error, {:css_compilation_failed, exit_code, error_output}}
      end
    after
      File.rm_rf([input_file, output_file])
    end
  end

  defp find_binary_path(%{tailwind_standalone_root: standalone_root}) do
    dist_dir = Path.join(standalone_root, "dist")

    if File.exists?(dist_dir) do
      case File.ls(dist_dir) do
        {:ok, files} ->
          # Look for macOS ARM64 binary first, then any executable
          macos_binary = Enum.find(files, &String.contains?(&1, "macos-arm64"))
          executable = macos_binary || Enum.find(files, &(not String.contains?(&1, ".")))

          if executable do
            Path.join(dist_dir, executable)
          else
            nil
          end

        {:error, _} ->
          nil
      end
    else
      nil
    end
  end

  defp find_binary_path(_), do: nil

  defp send_test_update(monitor_pid, event_type, data) when is_pid(monitor_pid) do
    send(
      monitor_pid,
      {:test_progress,
       %{
         type: event_type,
         data: data,
         timestamp: System.system_time(:millisecond)
       }}
    )
  end

  ## Example Usage Functions

  @doc """
  Example: Run basic v4 test with live monitoring
  """
  def example_monitored_test do
    working_dir = "/tmp/tailwind_quick_test"

    # Start monitoring in current process
    test_pid =
      spawn(fn ->
        case run_with_monitoring(:v4_basic, working_dir, self()) do
          {:ok, result} ->
            IO.puts("✅ Test successful: #{result.scenario}")
            IO.puts("Duration: #{result.duration_ms}ms")
            IO.puts("Performance: #{Float.round(result.performance_ratio * 100, 1)}% of expected")

          {:error, reason} ->
            IO.puts("❌ Test failed: #{inspect(reason)}")
        end
      end)

    # Listen for progress updates
    listen_for_progress(test_pid)
  end

  defp listen_for_progress(test_pid) do
    # 3 minute timeout
    receive do
      {:build_progress, event} ->
        IO.puts("[BUILD] #{event.message}")
        listen_for_progress(test_pid)

      {:test_progress, event} ->
        IO.puts("[TEST] #{format_test_event(event)}")
        listen_for_progress(test_pid)
    after
      180_000 ->
        IO.puts("⏰ Test timeout")
    end
  end

  defp format_test_event(%{type: :test_start, data: scenario}) do
    "🧪 Starting: #{scenario.description}"
  end

  defp format_test_event(%{type: :download_start}) do
    "📥 Downloading source..."
  end

  defp format_test_event(%{type: :plugin_start}) do
    "🔌 Adding plugins..."
  end

  defp format_test_event(%{type: :build_start}) do
    "🏗️  Building binary..."
  end

  defp format_test_event(%{type: :test_binary_start}) do
    "🧪 Testing functionality..."
  end

  defp format_test_event(%{type: :test_success, data: %{result: result}}) do
    "✅ Success! (#{result.duration_ms}ms)"
  end

  defp format_test_event(%{type: :test_error, data: %{error: error}}) do
    "❌ Failed: #{inspect(error)}"
  end

  defp format_test_event(%{type: type}) do
    "◦ #{String.replace(to_string(type), "_", " ")}"
  end
end
