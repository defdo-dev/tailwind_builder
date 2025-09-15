defmodule Defdo.TailwindBuilder.Dependencies do
  @moduledoc """
  Manages build dependencies for TailwindBuilder

  This module handles:
  - Basic tools installation (Node.js, Rust, npm, pnpm)
  - Rust target management for TailwindCSS v4.x
  - System dependency validation
  - Automatic target installation for WebAssembly compilation
  """
  require Logger

  @required_tools ~w(npm pnpm node cargo rustup)
  @required_rust_targets ~w(wasm32-wasip1-threads)
  @tailwind_v4_requirements %{
    "4.0.0" => ["wasm32-wasip1-threads"],
    "4.1.0" => ["wasm32-wasip1-threads"],
    "4.1.11" => ["wasm32-wasip1-threads"]
  }

  def check! do
    case missing_tools() do
      [] ->
        :ok

      missing ->
        raise """
        Missing required build tools: #{Enum.join(missing, ", ")}

        You can install them manually:
        - Rust (for cargo): curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        - Node.js (for npm):
          Ubuntu: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs
          macOS: brew install node
        - pnpm: npm install -g pnpm
        Or run: mix tailwind.install_deps
        """
    end
  end

  @doc """
  Checks if system has all dependencies required for a specific Tailwind version
  """
  def check_version_dependencies!(version) do
    # First check basic tools
    check!()

    # Then check version-specific requirements
    case check_rust_targets_for_version(version) do
      {:ok, _} -> :ok
      {:error, missing_targets} ->
        install_missing_rust_targets!(missing_targets)
    end
  end

  @doc """
  Validates system dependencies and returns detailed status
  """
  def check_system_dependencies do
    %{
      node: is_installed?("node"),
      npm: is_installed?("npm"),
      pnpm: is_installed?("pnpm"),
      rust: is_installed?("cargo"),
      rustup: is_installed?("rustup"),
      git: is_installed?("git"),
      rust_targets: get_installed_rust_targets()
    }
  end

  def install! do
    Logger.info("Installing build dependencies...")

    cond do
      is_installed?("asdf") ->
        Logger.info("Using asdf to install dependencies")
        System.cmd("asdf", ["plugin", "add", "nodejs"], into: IO.stream())
        System.cmd("asdf", ["plugin", "add", "rust"], into: IO.stream())
        System.cmd("asdf", ["install", "nodejs", "latest"], into: IO.stream())
        System.cmd("asdf", ["install", "rust", "latest"], into: IO.stream())
        System.cmd("asdf", ["global", "nodejs", "latest"], into: IO.stream())
        System.cmd("asdf", ["global", "rust", "latest"], into: IO.stream())
        System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())

      is_installed?("brew") ->
        Logger.info("Using homebrew to install dependencies")
        System.cmd("brew", ["install", "node"], into: IO.stream())
        System.cmd("brew", ["install", "rust"], into: IO.stream())
        System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())

      true ->
        Logger.info("Using direct installation methods")

        System.cmd("curl", ["--proto", "=https", "--tlsv1.2", "-sSf", "https://sh.rustup.rs"],
          into: IO.stream()
        )

        # For other systems, try direct Node.js installation
        System.cmd("curl", ["-o", "node.pkg", "https://nodejs.org/dist/latest/node-latest.pkg"],
          into: IO.stream()
        )

        System.cmd("sudo", ["installer", "-pkg", "node.pkg", "-target", "/"], into: IO.stream())
        System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())
    end

    # Install required Rust targets after Rust is installed
    install_rust_targets!()

    :ok
  end

  @doc """
  Installs required Rust targets for TailwindCSS v4.x compilation
  """
  def install_rust_targets! do
    Logger.info("Installing required Rust targets...")

    for target <- @required_rust_targets do
      install_rust_target!(target)
    end

    :ok
  end

  @doc """
  Installs missing Rust targets for a specific list
  """
  def install_missing_rust_targets!(missing_targets) when is_list(missing_targets) do
    Logger.info("Installing missing Rust targets: #{inspect(missing_targets)}")

    for target <- missing_targets do
      install_rust_target!(target)
    end

    :ok
  end

  @doc """
  Installs a specific Rust target
  """
  def install_rust_target!(target) do
    Logger.info("Installing Rust target: #{target}")

    case System.cmd("rustup", ["target", "add", target]) do
      {output, 0} ->
        Logger.info("Successfully installed Rust target #{target}: #{String.trim(output)}")
        :ok
      {error_output, exit_code} ->
        Logger.error("Failed to install Rust target #{target} (exit #{exit_code}): #{error_output}")
        {:error, {:target_install_failed, target, exit_code, error_output}}
    end
  end

  def uninstall! do
    Logger.info("Uninstalling build dependencies...")

    # Try to uninstall pnpm first while npm is still available
    if is_installed?("npm") do
      Logger.info("Removing pnpm...")
      System.cmd("npm", ["uninstall", "-g", "pnpm"], into: IO.stream())
    end

    cond do
      is_installed?("asdf") ->
        Logger.info("Uninstalling via asdf")

        # Check if plugins exist before trying to uninstall
        {plugins_output, 0} = System.cmd("asdf", ["plugin", "list"])
        plugins = String.split(plugins_output, "\n")

        if "nodejs" in plugins do
          System.cmd("asdf", ["uninstall", "nodejs"], into: IO.stream())
          System.cmd("asdf", ["plugin", "remove", "nodejs"], into: IO.stream())
        end

        if "rust" in plugins do
          System.cmd("asdf", ["uninstall", "rust"], into: IO.stream())
          System.cmd("asdf", ["plugin", "remove", "rust"], into: IO.stream())
        end

      is_installed?("brew") ->
        Logger.info("Uninstalling via homebrew")
        System.cmd("brew", ["uninstall", "node"], into: IO.stream())
        System.cmd("brew", ["uninstall", "rust"], into: IO.stream())

      true ->
        Logger.info("Manual uninstallation required")
        Logger.info("Please remove manually:")
        Logger.info("- Node.js: sudo rm -rf /usr/local/bin/node /usr/local/bin/npm")
        Logger.info("- Rust: rustup self uninstall")
    end

    :ok
  end

  @doc """
  Checks if required Rust targets are installed for a specific Tailwind version
  """
  def check_rust_targets_for_version(version) do
    required_targets = Map.get(@tailwind_v4_requirements, version, [])
    installed_targets = get_installed_rust_targets()

    missing_targets = Enum.reject(required_targets, fn target ->
      target in installed_targets
    end)

    case missing_targets do
      [] -> {:ok, required_targets}
      missing -> {:error, missing}
    end
  end

  @doc """
  Gets list of installed Rust targets
  """
  def get_installed_rust_targets do
    case System.cmd("rustup", ["target", "list", "--installed"]) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      {_error, _exit_code} ->
        Logger.warning("Could not retrieve installed Rust targets")
        []
    end
  end

  @doc """
  Validates that all Rust targets for a version are available
  """
  def validate_rust_targets_for_version!(version) do
    case check_rust_targets_for_version(version) do
      {:ok, _targets} -> :ok
      {:error, missing_targets} ->
        raise """
        Missing required Rust targets for TailwindCSS #{version}: #{Enum.join(missing_targets, ", ")}

        Install them with:
        #{Enum.map(missing_targets, fn target -> "rustup target add #{target}" end) |> Enum.join("\n")}

        Or run: Defdo.TailwindBuilder.Dependencies.install_missing_rust_targets!(#{inspect(missing_targets)})
        """
    end
  end

  defp missing_tools do
    Enum.reject(@required_tools, &is_installed?/1)
  end

  defp is_installed?(program) do
    if System.find_executable("#{program}"), do: true, else: false
  end
end
