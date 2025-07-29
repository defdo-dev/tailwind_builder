defmodule Defdo.TailwindBuilder.Builder do
  @moduledoc """
  Módulo especializado en la compilación de Tailwind CSS.
  
  Responsabilidades:
  - Compilar código fuente de Tailwind usando diferentes toolchains
  - Manejar diferencias entre v3 (npm) y v4 (Rust/pnpm) 
  - Ejecutar comandos de build con validación de herramientas
  - Reportar progreso y errores de compilación
  
  No maneja descarga ni plugins, solo la compilación del código.
  """
  
  require Logger
  alias Defdo.TailwindBuilder.Core

  @doc """
  Compila un proyecto de Tailwind CSS
  """
  def compile(opts \\ []) do
    opts = Keyword.validate!(opts, [
      :version,
      :source_path,
      :debug,
      :validate_tools
    ])
    
    version = opts[:version] || raise ArgumentError, "version is required"
    source_path = opts[:source_path] || raise ArgumentError, "source_path is required"
    debug = Keyword.get(opts, :debug, false)
    validate_tools = Keyword.get(opts, :validate_tools, true)
    
    with {:validate_tools, :ok} <- {:validate_tools, maybe_validate_tools(version, validate_tools)},
         {:validate_paths, {:ok, paths}} <- {:validate_paths, validate_and_get_paths(source_path, version)},
         {:compile, :ok} <- {:compile, execute_compilation(version, paths, debug)} do
      
      result = %{
        version: version,
        compilation_method: Core.get_compilation_method(version),
        source_path: source_path,
        tailwind_root: paths.tailwind_root,
        standalone_root: paths.standalone_root,
        debug_mode: debug
      }
      
      {:ok, result}
    else
      {step, error} ->
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
    timeout = Keyword.get(opts, :timeout, 300_000)  # 5 minutos default
    
    Logger.info("Executing: #{command} #{Enum.join(args, " ")} in #{working_dir}")
    
    system_opts = [
      cd: working_dir,
      stderr_to_stdout: not debug
    ]
    
    system_opts = if timeout do
      [{:timeout, timeout} | system_opts]
    else
      system_opts
    end
    
    case System.cmd(command, args, system_opts) do
      {output, 0} ->
        if debug, do: Logger.info("Command output: #{output}")
        {:ok, output}
      
      {output, exit_code} ->
        Logger.error("Command failed with exit code #{exit_code}")
        Logger.error("Output: #{output}")
        {:error, {:command_failed, exit_code, output}}
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

  defp execute_compilation(version, paths, debug) do
    constraints = Core.get_version_constraints(version)
    
    case constraints.major_version do
      :v3 -> compile_v3(paths, debug)
      :v4 -> compile_v4(paths, debug)
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

  defp compile_v4(paths, debug) do
    steps = [
      {"pnpm install (root)", "pnpm", ["install", "--no-frozen-lockfile"], paths.tailwind_root},
      {"pnpm build (root)", "pnpm", ["run", "build"], paths.tailwind_root},
      {"pnpm rebuild (standalone)", "pnpm", ["run", "build"], paths.standalone_root}
    ]
    
    execute_compilation_steps(steps, debug)
  end

  defp execute_compilation_steps(steps, debug) do
    Enum.reduce_while(steps, :ok, fn {step_name, command, args, working_dir}, _acc ->
      Logger.info("Starting step: #{step_name}")
      
      case execute_build_command(command, args, cd: working_dir, debug: debug) do
        {:ok, _output} ->
          Logger.info("Completed step: #{step_name}")
          {:cont, :ok}
        
        {:error, reason} ->
          Logger.error("Failed step: #{step_name} - #{inspect(reason)}")
          {:halt, {:error, {String.to_atom(step_name), reason}}}
      end
    end)
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