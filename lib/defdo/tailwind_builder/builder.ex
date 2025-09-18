defmodule Defdo.TailwindBuilder.Builder do
  @moduledoc """
  Specialized module for Tailwind CSS compilation with comprehensive telemetry.

  Responsibilities:
  - Compile Tailwind source code using different toolchains
  - Handle differences between v3 (npm) and v4 (Rust/pnpm)
  - Execute build commands with tool validation
  - Report progress and compilation errors with telemetry
  - Performance monitoring for build processes

  Does not handle downloads or plugins, only code compilation.
  """

  require Logger
  alias Defdo.TailwindBuilder.{Core, Telemetry, Metrics}

  @doc """
  Compile a Tailwind CSS project with comprehensive telemetry tracking

  ## Options
  - `:version` - TailwindCSS version to compile
  - `:source_path` - Path to TailwindCSS source code
  - `:debug` - Enable debug mode
  - `:target_arch` - Target architecture for cross-compilation (v4 only)
  - `:validate_tools` - Whether to validate required tools
  """
  def compile(opts \\ []) do
    # Check Rust targets before compilation for v4.x
    version = opts[:version] || "unknown"

    # Validate dependencies including Rust targets for v4.x
    case String.starts_with?(version, "4.") do
      true ->
        try do
          Defdo.TailwindBuilder.Dependencies.check_version_dependencies!(version)

          # Use telemetry wrapper for comprehensive tracking
          plugins = extract_plugins_from_opts(opts)

          Telemetry.track_build(version, plugins, fn ->
            do_compile(opts)
          end)
        rescue
          error ->
            Logger.error("Dependency validation failed: #{Exception.message(error)}")
            {:error, {:dependency_check_failed, Exception.message(error)}}
        end
      false ->
        # Use telemetry wrapper for comprehensive tracking
        plugins = extract_plugins_from_opts(opts)

        Telemetry.track_build(version, plugins, fn ->
          do_compile(opts)
        end)
    end
  end

  defp do_compile(opts) do
    opts = Keyword.validate!(opts, [
      :version,
      :source_path,
      :debug,
      :validate_tools,
      :target_arch
    ])

    version = opts[:version] || raise ArgumentError, "version is required"
    source_path = opts[:source_path] || raise ArgumentError, "source_path is required"
    debug = Keyword.get(opts, :debug, false)
    validate_tools = Keyword.get(opts, :validate_tools, true)
    target_arch = opts[:target_arch]

    # Track build start
    start_time = System.monotonic_time()
    compilation_method = Core.get_compilation_method(version)
    Telemetry.track_event(:build, :start, %{
      version: version,
      source_path: source_path,
      compilation_method: compilation_method,
      debug: debug
    })

    with {:validate_tools, :ok} <- {:validate_tools, maybe_validate_tools_with_telemetry(version, validate_tools)},
         {:validate_paths, {:ok, paths}} <- {:validate_paths, validate_and_get_paths_with_telemetry(source_path, version)},
         {:compile, compilation_result} <- {:compile, execute_compilation_with_telemetry(version, paths, debug, target_arch)} do
      Logger.debug("Compilation result: #{inspect(compilation_result)}")

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Calculate output size if possible
      output_size = calculate_output_size(paths)

      result = %{
        version: version,
        compilation_method: compilation_method,
        source_path: source_path,
        tailwind_root: paths.tailwind_root,
        standalone_root: paths.standalone_root,
        debug_mode: debug,
        duration_ms: duration_ms,
        output_size_bytes: output_size
      }

      # Record comprehensive metrics
      plugins = extract_plugins_from_paths(paths)
      Metrics.record_build_metrics(version, plugins, duration_ms, output_size, :success)
      Telemetry.track_event(:build, :success, %{
        version: version,
        duration_ms: duration_ms,
        output_size_bytes: output_size,
        compilation_method: compilation_method
      })

      {:ok, result}
    else
      {step, error} ->
        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        # Record error metrics
        plugins = extract_plugins_from_opts(opts)
        Metrics.record_error_metrics(:build, step, error)
        Metrics.record_build_metrics(version, plugins, duration_ms, 0, :error)
        Telemetry.track_event(:build, :error, %{
          version: version,
          step: step,
          error: inspect(error),
          duration_ms: duration_ms,
          compilation_method: compilation_method
        })

        Logger.error("Compilation failed at step #{step}: #{inspect(error)}")
        {:error, {step, error}}
    end
  end

  @doc """
  Verifica si las herramientas necesarias están disponibles
  """
  def validate_required_tools(version) do
    constraints = Core.get_version_constraints(version)
    required_tools = constraints.required_tools

    missing_tools = Enum.reject(required_tools, fn tool ->
      tool_available?(tool)
    end)

    case missing_tools do
      [] -> :ok
      tools -> {:error, {:missing_tools, tools}}
    end
  end

  @doc """
  Obtiene información sobre los requisitos de compilación
  """
  def get_compilation_info(version) do
    constraints = Core.get_version_constraints(version)
    compilation_details = Core.get_compilation_details(version)

    %{
      version: version,
      compilation_method: constraints.compilation_method,
      required_tools: constraints.required_tools,
      optional_tools: constraints.optional_tools,
      build_commands: constraints.file_structure.build_commands,
      working_directory: constraints.file_structure.base_path,
      cross_compilation: constraints.cross_compilation,
      limitations: compilation_details.limitations,
      runtime_constraints: constraints.runtime_constraints
    }
  end

  @doc """
  Verifica si una herramienta está disponible en el sistema
  """
  def tool_available?(tool_name) when is_binary(tool_name) do
    case System.find_executable(tool_name) do
      nil -> false
      _path -> true
    end
  end

  @doc """
  Ejecuta un comando de compilación con logging apropiado
  """
  def execute_build_command(command, args, opts \\ []) do
    working_dir = Keyword.get(opts, :cd)
    debug = Keyword.get(opts, :debug, false)
    timeout = Keyword.get(opts, :timeout, 900_000)  # 15 minutos default
    version = Keyword.get(opts, :version)

    # V4 uses Rust/Cargo, not pnpm/bun/napi
    do_execute_build_command(command, args, working_dir, debug, timeout, version)
  end

  defp do_execute_build_command(command, args, working_dir, debug, timeout, version) do
    Logger.info("Executing: #{command} #{Enum.join(args, " ")} in #{working_dir}")

    # Get build context for telemetry
    build_context = Process.get(:build_telemetry_context, %{})

    # Emit telemetry for command start
    command_metadata = Map.merge(%{
      command: command,
      args: args,
      working_dir: working_dir,
      version: version
    }, build_context)

    :telemetry.execute(
      [:tailwind_builder, :build, :command, :start],
      %{system_time: System.system_time()},
      command_metadata
    )

    # Set environment variables for TailwindCSS v4.x builds
    env_vars = case {command, version} do
      {"pnpm", v} when is_binary(v) and binary_part(v, 0, 2) == "4." ->
        [{"CARGO_PROFILE_RELEASE_LTO", "off"}, {"CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER", "lld-link"}]
      _ ->
        []
    end

    system_opts = [
      cd: working_dir,
      stderr_to_stdout: not debug,
      env: env_vars
    ]

    # Use Task.async/await for timeout support in Elixir 1.18+
    task = Task.async(fn ->
      System.cmd(command, args, system_opts)
    end)

    try do
      case Task.await(task, timeout) do
        {output, 0} ->
          if debug, do: Logger.info("Command output: #{output}")

          # Emit telemetry for successful command completion
          success_metadata = Map.merge(command_metadata, %{result: :success, exit_code: 0})
          :telemetry.execute(
            [:tailwind_builder, :build, :command, :stop],
            %{system_time: System.system_time()},
            success_metadata
          )

          {:ok, output}

        {output, exit_code} ->
          Logger.error("Command failed with exit code #{exit_code}")
          Logger.error("Output: #{output}")

          # Emit telemetry for failed command completion
          failure_metadata = Map.merge(command_metadata, %{
            result: :error,
            exit_code: exit_code,
            error_output: String.slice(output, 0, 500) # Limit error output size
          })
          :telemetry.execute(
            [:tailwind_builder, :build, :command, :stop],
            %{system_time: System.system_time()},
            failure_metadata
          )

          {:error, {:command_failed, exit_code, output}}
      end
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        Logger.error("Command timed out after #{timeout}ms")

        # Emit telemetry for timeout
        timeout_metadata = Map.merge(command_metadata, %{
          result: :timeout,
          timeout_ms: timeout
        })
        :telemetry.execute(
          [:tailwind_builder, :build, :command, :stop],
          %{system_time: System.system_time()},
          timeout_metadata
        )

        {:error, {:timeout, timeout}}
    end
  end


  @doc """
  Obtiene las rutas de archivos necesarias para la compilación
  """
  def get_build_paths(source_path, version) do
    constraints = Core.get_version_constraints(version)

    case constraints.major_version do
      :v3 -> get_v3_paths(source_path, version)
      :v4 -> get_v4_paths(source_path, version)
      _ -> {:error, :unsupported_version}
    end
  end

  @doc """
  Get list of required tools for building a specific version
  """
  def get_required_tools(version) do
    constraints = Core.get_version_constraints(version)
    constraints.required_tools
  end

  # Funciones privadas

  defp maybe_validate_tools(version, true), do: validate_required_tools(version)
  defp maybe_validate_tools(_version, false), do: :ok

  # Telemetry-enhanced versions of internal functions

  defp maybe_validate_tools_with_telemetry(version, validate_flag) do
    Telemetry.track_event(:build, :tool_validation_start, %{version: version, validate: validate_flag})

    result = maybe_validate_tools(version, validate_flag)

    case result do
      :ok ->
        Telemetry.track_event(:build, :tool_validation_success, %{version: version})
      error ->
        Telemetry.track_event(:build, :tool_validation_error, %{version: version, error: inspect(error)})
    end

    result
  end

  defp validate_and_get_paths_with_telemetry(source_path, version) do
    start_time = System.monotonic_time()
    Telemetry.track_event(:build, :path_validation_start, %{source_path: source_path, version: version})

    result = validate_and_get_paths(source_path, version)

    end_time = System.monotonic_time()
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

    case result do
      {:ok, paths} ->
        Telemetry.track_event(:build, :path_validation_success, %{
          source_path: source_path,
          version: version,
          duration_ms: duration_ms,
          tailwind_root: paths.tailwind_root,
          standalone_root: paths.standalone_root
        })

      error ->
        Telemetry.track_event(:build, :path_validation_error, %{
          source_path: source_path,
          version: version,
          error: inspect(error),
          duration_ms: duration_ms
        })
    end

    result
  end

  defp execute_compilation_with_telemetry(version, paths, debug, target_arch) do
    start_time = System.monotonic_time()
    compilation_method = Core.get_compilation_method(version)

    Telemetry.track_event(:build, :compilation_start, %{
      version: version,
      compilation_method: compilation_method,
      debug: debug,
      tailwind_root: paths.tailwind_root
    })

    result = execute_compilation(version, paths, debug, target_arch)

    end_time = System.monotonic_time()
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

    case result do
      {:ok, _} = success ->
        Telemetry.track_event(:build, :compilation_success, %{
          version: version,
          compilation_method: compilation_method,
          duration_ms: duration_ms,
          debug: debug
        })
        success

      {:error, _} = error ->
        Telemetry.track_event(:build, :compilation_error, %{
          version: version,
          compilation_method: compilation_method,
          error: inspect(error),
          duration_ms: duration_ms,
          debug: debug
        })
        error
    end
  end

  # Utility functions for telemetry

  defp extract_plugins_from_opts(opts) do
    # Extract plugin information from options if available
    Keyword.get(opts, :plugins, [])
  end

  defp extract_plugins_from_paths(paths) do
    # Try to extract plugins from package.json or other config files
    try do
      package_json_path = Path.join(paths.tailwind_root, "package.json")
      if File.exists?(package_json_path) do
        package_json_path
        |> File.read!()
        |> Jason.decode!()
        |> get_in(["dependencies"])
        |> Map.keys()
        |> Enum.filter(&String.contains?(&1, "tailwind"))
      else
        []
      end
    rescue
      _ -> []
    end
  end

  defp calculate_output_size(paths) do
    # Calculate total size of build outputs
    try do
      build_dirs = [
        Path.join(paths.tailwind_root, "dist"),
        Path.join(paths.tailwind_root, "build"),
        Path.join(paths.standalone_root, "dist")
      ]

      build_dirs
      |> Enum.filter(&File.exists?/1)
      |> Enum.reduce(0, fn dir, acc ->
        acc + calculate_directory_size(dir)
      end)
    rescue
      _ -> 0
    end
  end

  defp calculate_directory_size(dir) do
    dir
    |> File.ls!()
    |> Enum.reduce(0, fn file, acc ->
      file_path = Path.join(dir, file)
      case File.stat(file_path) do
        {:ok, %{size: size, type: :regular}} -> acc + size
        {:ok, %{type: :directory}} -> acc + calculate_directory_size(file_path)
        _ -> acc
      end
    end)
  rescue
    _ -> 0
  end

  defp validate_and_get_paths(source_path, version) do
    case get_build_paths(source_path, version) do
      {:ok, paths} ->
        if validate_paths_exist(paths) do
          {:ok, paths}
        else
          {:error, {:invalid_paths, "Required build paths not found"}}
        end

      error -> error
    end
  end

  defp validate_paths_exist(paths) do
    File.exists?(paths.tailwind_root) and
    (is_nil(paths.standalone_root) or File.exists?(paths.standalone_root))
  end

  defp execute_compilation(version, paths, debug, target_arch) do
    constraints = Core.get_version_constraints(version)

    case constraints.major_version do
      :v3 -> compile_v3(paths, debug)
      :v4 -> compile_v4(paths, debug, version, target_arch)
      :v5 -> compile_v5(paths, debug, version, target_arch)
      :v6 -> compile_v6(paths, debug, version, target_arch)
      _ -> {:error, :unsupported_version}
    end
  end

  defp compile_v3(paths, debug) do
    steps = [
      {"npm install (root)", "npm", ["install"], paths.tailwind_root},
      {"npm build (root)", "npm", ["run", "build"], paths.tailwind_root},
      {"npm install (standalone)", "npm", ["install"], paths.standalone_root},
      {"npm build (standalone)", "npm", ["run", "build"], paths.standalone_root}
    ]

    execute_compilation_steps(steps, debug)
  end

  defp compile_v4(paths, debug, version, target_arch) do
    # TailwindCSS v4 uses pnpm workspace + Rust compilation (official method)
    Logger.info("Building TailwindCSS v4 using pnpm workspace + Rust (official method)")

    # Build pnpm commands following official GitHub Actions workflow
    install_step = {"pnpm install", "pnpm", ["install"], paths.tailwind_root}

    # Build the oxide crate for the target platform
    oxide_build_step = if target_arch do
      Logger.info("Cross-compiling oxide for target: #{target_arch}")
      {"pnpm oxide build", "pnpm", ["run", "--filter", "./crates/node", "build:platform", "--target=#{target_arch}"], paths.tailwind_root}
    else
      {"pnpm oxide build", "pnpm", ["run", "--filter", "./crates/node", "build:platform"], paths.tailwind_root}
    end

    # Build the entire workspace first
    workspace_build_step = {"pnpm workspace build", "pnpm", ["run", "build"], paths.tailwind_root}

    # Build standalone binaries using the official script
    standalone_build_step = {"bun standalone build", "bun", ["run", "build"], Path.join(paths.tailwind_root, "packages/@tailwindcss-standalone")}

    steps = [install_step, oxide_build_step, workspace_build_step, standalone_build_step]

    execute_compilation_steps(steps, debug, version)
  end

  defp compile_v5(paths, debug, version, target_arch) do
    # TailwindCSS v5 - assume continued Rust-based approach
    Logger.info("Building TailwindCSS v5 using Rust/Cargo (future version)")

    # Build Cargo command with optional target architecture
    cargo_args = if target_arch do
      Logger.info("Cross-compiling for target: #{target_arch}")
      ["build", "--release", "--target", target_arch]
    else
      ["build", "--release"]
    end

    steps = [
      {"cargo build (release)", "cargo", cargo_args, paths.tailwind_root}
    ]

    execute_compilation_steps(steps, debug, version)
  end

  defp compile_v6(paths, debug, version, target_arch) do
    # TailwindCSS v6 - assume continued Rust-based approach
    Logger.info("Building TailwindCSS v6 using Rust/Cargo (future version)")

    # Build Cargo command with optional target architecture
    cargo_args = if target_arch do
      Logger.info("Cross-compiling for target: #{target_arch}")
      ["build", "--release", "--target", target_arch]
    else
      ["build", "--release"]
    end

    steps = [
      {"cargo build (release)", "cargo", cargo_args, paths.tailwind_root}
    ]

    execute_compilation_steps(steps, debug, version)
  end

  defp execute_compilation_steps(steps, debug, version \\ nil) do
    # Get build context if available
    build_context = Process.get(:build_telemetry_context, %{})

    result = Enum.reduce_while(steps, :ok, fn {step_name, command, args, working_dir}, _acc ->
      Logger.info("Starting step: #{step_name}")

      # Emit telemetry event for step start with build context
      telemetry_metadata = Map.merge(%{step: step_name, version: version}, build_context)
      Logger.info("[BUILDER] Emitting step start telemetry: #{inspect(telemetry_metadata)}")
      :telemetry.execute(
        [:tailwind_builder, :build, :step, :start],
        %{system_time: System.system_time()},
        telemetry_metadata
      )

      case execute_build_command(command, args, cd: working_dir, debug: debug, version: version) do
        {:ok, _output} ->
          Logger.info("Completed step: #{step_name}")

          # Emit telemetry event for step completion with build context
          completion_metadata = Map.merge(%{step: step_name, version: version, result: :success}, build_context)
          Logger.info("[BUILDER] Emitting step stop telemetry: #{inspect(completion_metadata)}")
          :telemetry.execute(
            [:tailwind_builder, :build, :step, :stop],
            %{system_time: System.system_time()},
            completion_metadata
          )

          {:cont, :ok}

        {:error, reason} ->
          Logger.error("Failed step: #{step_name} - #{inspect(reason)}")

          # Emit telemetry event for step failure with build context
          failure_metadata = Map.merge(%{step: step_name, version: version, result: :error, error: inspect(reason)}, build_context)
          :telemetry.execute(
            [:tailwind_builder, :build, :step, :stop],
            %{system_time: System.system_time()},
            failure_metadata
          )

          {:halt, {:error, {String.to_atom(step_name), reason}}}
      end
    end)

    # Convert :ok to {:ok, result} for consistency
    case result do
      :ok -> {:ok, %{status: :compilation_completed, steps_completed: length(steps)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_v3_paths(source_path, version) do
    tailwind_root = Path.join(source_path, "tailwindcss-#{version}")
    standalone_root = Path.join([source_path, "tailwindcss-#{version}", "standalone-cli"])

    {:ok, %{
      tailwind_root: tailwind_root,
      standalone_root: standalone_root,
      dist_path: Path.join(standalone_root, "dist")
    }}
  end

  defp get_v4_paths(source_path, version) do
    tailwind_root = Path.join(source_path, "tailwindcss-#{version}")
    standalone_root = Path.join([source_path, "tailwindcss-#{version}", "packages", "@tailwindcss-standalone"])

    {:ok, %{
      tailwind_root: tailwind_root,
      standalone_root: standalone_root,
      dist_path: Path.join(standalone_root, "dist")
    }}
  end
end
