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

  @required_tools ~w(npm pnpm node cargo rustup bun)

  # Rust target required for TailwindCSS v4 Oxide compilation (always needed for v4.x)
  @wasm_target "wasm32-wasip1-threads"

  # Native targets by platform - we do NOT cross-compile, each node builds natively
  @platform_specific_targets %{
    # macOS (native targets are already installed by Rust, no musl needed)
    {:darwin, :arm64} => [],
    {:darwin, :x64} => [],

    # Linux (compile both gnu and musl variants like official Tailwind)
    # - gnu: uses glibc, dynamically linked, faster to compile
    # - musl: uses musl libc, statically linked, more portable
    {:linux, :x64} => ["x86_64-unknown-linux-gnu", "x86_64-unknown-linux-musl"],
    {:linux, :arm64} => ["aarch64-unknown-linux-gnu", "aarch64-unknown-linux-musl"],

    # Windows
    {:win32, :x64} => ["x86_64-pc-windows-msvc"]
  }

  # Get targets required for current platform
  defp get_required_rust_targets do
    platform_key = {host_os(), host_arch()}
    platform_targets = Map.get(@platform_specific_targets, platform_key, [])
    [@wasm_target | platform_targets]
  end

  defp host_os do
    case :os.type() do
      {:unix, :darwin} -> :darwin
      {:unix, :linux} -> :linux
      {:win32, _} -> :win32
      _ -> :unknown
    end
  end

  defp host_arch do
    arch = :erlang.system_info(:system_architecture) |> to_string()

    cond do
      String.contains?(arch, "aarch64") or String.contains?(arch, "arm64") -> :arm64
      String.contains?(arch, "x86_64") or String.contains?(arch, "amd64") -> :x64
      true -> :unknown
    end
  end

  defp asdf_version do
    if is_installed?("asdf") do
      {out, _} = System.cmd("asdf", ["--version"])
      # Ejemplos de out:
      # "v0.17.0 (revision ...)"
      # "version: v0.16.3"
      case Regex.run(~r/v?(\d+)\.(\d+)\.(\d+)/, out || "") do
        [_, maj, min, patch] ->
          {String.to_integer(maj), String.to_integer(min), String.to_integer(patch)}

        _ ->
          {0, 0, 0}
      end
    else
      {0, 0, 0}
    end
  end

  # Usa comparación de tuplas para checar si soporta `asdf set`
  defp asdf_supports_set? do
    asdf_version() >= {0, 17, 0}
  end

  defp asdf_set!(tool, version, cwd) do
    if asdf_supports_set?() do
      System.cmd("asdf", ["set", tool, version], into: IO.stream(), cd: cwd)
      System.cmd("asdf", ["set", "--home", tool, version], into: IO.stream())
    else
      # Fallback para asdf antiguos
      System.cmd("asdf", ["local", tool, version], into: IO.stream(), cd: cwd)
      System.cmd("asdf", ["global", tool, version], into: IO.stream())
    end
  end

  # Ejecuta comandos a través de asdf cuando exista
  defp asdf_exec(cmd, args) do
    if is_installed?("asdf") do
      System.cmd("asdf", ["exec", cmd | args])
    else
      System.cmd(cmd, args)
    end
  end

  defp latest_with_asdf!(name) do
    case System.cmd("asdf", ["latest", name]) do
      {out, 0} -> String.trim(out)
      {err, code} -> raise "Failed to get latest #{name} from asdf (exit #{code}): #{err}"
    end
  end

  def check! do
    case missing_tools() do
      [] ->
        :ok

      missing ->
        raise """
        Missing required build tools: #{Enum.join(missing, ", ")}

        You can install them manually:
        - System dependencies (Ubuntu/Debian):
          sudo apt-get update && sudo apt-get install -y unzip curl
        - Rust (for cargo):
          asdf: asdf install rust latest && asdf global rust latest
          mise: mise install rust@latest && mise use -g rust@latest
          manual: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        - Node.js (for npm):
          Ubuntu: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs
          macOS: brew install node
          asdf: asdf install nodejs latest && asdf global nodejs latest
          mise: mise install node@lts && mise use -g node@lts
        - pnpm: npm install -g pnpm
        - Bun:
          asdf: asdf install bun latest && asdf global bun latest
          mise: mise install bun@latest && mise use -g bun@latest
          brew: brew install bun
          manual: curl -fsSL https://bun.sh/install | bash
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
      {:ok, _} ->
        :ok

      {:error, missing_targets} ->
        install_missing_rust_targets!(missing_targets)
        :ok
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
      bun: is_installed?("bun"),
      rust_targets: get_installed_rust_targets()
    }
  end

  def install! do
    Logger.info("Installing build dependencies...")
    cwd = File.cwd!()

    cond do
      is_installed?("mise") ->
        Logger.info("Using mise to install dependencies")
        install_with_mise!(cwd)

      is_installed?("asdf") ->
        Logger.info("Using asdf to install dependencies")
        install_with_asdf!(cwd)

      is_installed?("brew") ->
        Logger.info("Using homebrew to install dependencies")
        System.cmd("brew", ["install", "node"], into: IO.stream())
        System.cmd("brew", ["install", "rust"], into: IO.stream())
        System.cmd("brew", ["install", "bun"], into: IO.stream())
        System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())

      true ->
        Logger.info("Using direct installation methods")
        install_direct!()
    end

    install_rust_targets!()
    :ok
  end

  defp install_with_mise!(_cwd) do
    # Ensure system dependencies are available on Linux
    if host_os() == :linux do
      Logger.info("Installing Linux system dependencies...")
      System.cmd("sudo", ["apt-get", "update"], into: IO.stream())

      System.cmd(
        "sudo",
        [
          "apt-get",
          "install",
          "-y",
          "unzip",
          "curl",
          "build-essential",
          "musl-tools",
          "musl-dev"
        ],
        into: IO.stream()
      )
    end

    # mise's 'use -g' command automatically installs and sets global version
    Logger.info("Installing Node.js via mise...")
    System.cmd("mise", ["use", "-g", "node"], into: IO.stream())

    Logger.info("Installing Rust via mise...")
    System.cmd("mise", ["use", "-g", "rust"], into: IO.stream())

    Logger.info("Installing Bun via mise...")
    System.cmd("mise", ["use", "-g", "bun"], into: IO.stream())

    # Install pnpm globally using mise's node
    Logger.info("Installing pnpm globally...")
    System.cmd("mise", ["exec", "--", "npm", "install", "-g", "pnpm"], into: IO.stream())

    Logger.info("""

    ⚠️  IMPORTANT: Shell reload required!
    Run this command to update your PATH:
      source ~/.bashrc  # or: source ~/.zshrc

    Then verify installation:
      bun --version
      cargo --version
      pnpm --version
    """)
  end

  defp install_with_asdf!(cwd) do
    # Ensure system dependencies are available on Linux
    if host_os() == :linux do
      Logger.info("Installing Linux system dependencies...")
      System.cmd("sudo", ["apt-get", "update"], into: IO.stream())

      System.cmd(
        "sudo",
        [
          "apt-get",
          "install",
          "-y",
          "unzip",
          "curl",
          "build-essential",
          "musl-tools",
          "musl-dev"
        ],
        into: IO.stream()
      )
    end

    System.cmd("asdf", ["plugin", "add", "nodejs"], into: IO.stream())
    System.cmd("asdf", ["plugin", "add", "rust"], into: IO.stream())
    System.cmd("asdf", ["plugin", "add", "bun"], into: IO.stream())

    node_latest = latest_with_asdf!("nodejs")
    rust_latest = latest_with_asdf!("rust")
    bun_latest = latest_with_asdf!("bun")

    System.cmd("asdf", ["install", "nodejs", node_latest], into: IO.stream())
    System.cmd("asdf", ["install", "rust", rust_latest], into: IO.stream())
    System.cmd("asdf", ["install", "bun", bun_latest], into: IO.stream())

    # Compat: asdf >= 0.17 usa 'set'; asdf viejos usan 'local'
    asdf_set!("nodejs", node_latest, cwd)
    asdf_set!("rust", rust_latest, cwd)
    asdf_set!("bun", bun_latest, cwd)

    System.cmd("asdf", ["reshim", "nodejs", node_latest], into: IO.stream())
    System.cmd("asdf", ["reshim", "rust", rust_latest], into: IO.stream())
    System.cmd("asdf", ["reshim", "bun", bun_latest], into: IO.stream())

    # Usa el Node de asdf
    System.cmd("asdf", ["exec", "npm", "install", "-g", "pnpm"], into: IO.stream())
  end

  defp install_direct! do
    case host_os() do
      :linux ->
        install_direct_linux!()

      :darwin ->
        install_direct_macos!()

      _ ->
        Logger.error("Unsupported operating system for direct installation")
        raise "Please install dependencies manually or use asdf/mise"
    end
  end

  defp install_direct_linux! do
    Logger.info("Installing dependencies on Linux...")

    # Install system dependencies including musl for cross-compilation
    Logger.info("Installing system dependencies (unzip, curl, build-essential, musl-tools)...")
    System.cmd("sudo", ["apt-get", "update"], into: IO.stream())

    System.cmd(
      "sudo",
      ["apt-get", "install", "-y", "unzip", "curl", "build-essential", "musl-tools", "musl-dev"],
      into: IO.stream()
    )

    # Install Rust
    Logger.info("Installing Rust...")

    System.cmd(
      "bash",
      ["-c", "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"],
      into: IO.stream()
    )

    # Install Node.js via NodeSource
    Logger.info("Installing Node.js...")

    System.cmd(
      "bash",
      ["-c", "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"],
      into: IO.stream()
    )

    System.cmd("sudo", ["apt-get", "install", "-y", "nodejs"], into: IO.stream())

    # Install pnpm
    Logger.info("Installing pnpm...")
    System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())

    # Install Bun
    Logger.info("Installing Bun...")
    System.cmd("bash", ["-c", "curl -fsSL https://bun.sh/install | bash"], into: IO.stream())

    Logger.info("""

    ⚠️  IMPORTANT: Shell reload required!
    Run this command to update your PATH:
      source ~/.bashrc  # or: source ~/.zshrc

    Then verify installation:
      bun --version
      cargo --version
      pnpm --version

    Tools installed to:
      ~/.bun/bin (Bun)
      ~/.cargo/bin (Rust)
    """)
  end

  defp install_direct_macos! do
    Logger.info("Installing dependencies on macOS...")

    # Install Rust
    System.cmd("curl", ["--proto", "=https", "--tlsv1.2", "-sSf", "https://sh.rustup.rs"],
      into: IO.stream()
    )

    # Install Node.js via pkg installer
    System.cmd("curl", ["-o", "/tmp/node.pkg", "https://nodejs.org/dist/latest/node-latest.pkg"],
      into: IO.stream()
    )

    System.cmd("sudo", ["installer", "-pkg", "/tmp/node.pkg", "-target", "/"], into: IO.stream())
    System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())

    # Install Bun
    System.cmd("bash", ["-c", "curl -fsSL https://bun.sh/install | bash"], into: IO.stream())
    Logger.info("If bun is not available yet, add ~/.bun/bin to your PATH")
  end

  @doc """
  Installs required Rust targets for TailwindCSS v4.x compilation

  On Linux, this installs BOTH gnu and musl targets:
    - *-gnu: Uses glibc (standard), no extra tools needed
    - *-musl: Uses musl libc (portable), requires musl-tools

  Ubuntu/Debian/Raspberry Pi (for musl support):
    sudo apt-get install -y musl-tools musl-dev

  See SETUP.md for complete pre-requisites
  """
  def install_rust_targets! do
    required_targets = get_required_rust_targets()

    Logger.info(
      "Installing required Rust targets for #{host_os()}-#{host_arch()}: #{inspect(required_targets)}"
    )

    # Warn Linux users about musl-tools requirement
    if host_os() == :linux and Enum.any?(required_targets, &String.contains?(&1, "musl")) do
      Logger.info("""

      📝 Note: Installing musl targets requires system packages.
      If musl target installation fails, install musl-tools first:
        Ubuntu/Debian/Raspberry Pi: sudo apt-get install -y musl-tools musl-dev
        Fedora/RHEL: sudo dnf install -y musl-gcc musl-devel
        Arch: sudo pacman -S musl
      """)
    end

    results =
      for target <- required_targets do
        install_rust_target!(target)
      end

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      {:error, reason} -> raise "Failed to install Rust targets: #{inspect(reason)}"
    end
  end

  @doc """
  Installs missing Rust targets for a specific list
  """
  def install_missing_rust_targets!(missing_targets) when is_list(missing_targets) do
    Logger.info("Installing missing Rust targets: #{inspect(missing_targets)}")

    results =
      for target <- missing_targets do
        install_rust_target!(target)
      end

    # Check if any installation failed
    case Enum.find(results, fn result -> match?({:error, _}, result) end) do
      nil -> :ok
      {:error, reason} -> raise "Failed to install Rust targets: #{inspect(reason)}"
    end
  end

  @doc """
  Installs a specific Rust target
  """
  def install_rust_target!(target) do
    Logger.info("Installing Rust target: #{target}")

    case asdf_exec("rustup", ["target", "add", target]) do
      {out, 0} ->
        Logger.info("Successfully installed Rust target #{target}: #{String.trim(out)}")
        :ok

      {err, code} ->
        Logger.error("Failed to install Rust target #{target} (exit #{code}): #{err}")
        {:error, {:target_install_failed, target, code, err}}
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

        if "bun" in plugins do
          System.cmd("asdf", ["uninstall", "bun"], into: IO.stream())
          System.cmd("asdf", ["plugin", "remove", "bun"], into: IO.stream())
        end

      is_installed?("brew") ->
        Logger.info("Uninstalling via homebrew")
        System.cmd("brew", ["uninstall", "node"], into: IO.stream())
        System.cmd("brew", ["uninstall", "rust"], into: IO.stream())
        System.cmd("brew", ["uninstall", "bun"], into: IO.stream())

      true ->
        Logger.info("Manual uninstallation required")
        Logger.info("Please remove manually:")
        Logger.info("- Node.js: sudo rm -rf /usr/local/bin/node /usr/local/bin/npm")
        Logger.info("- Rust: rustup self uninstall")
        Logger.info("- Bun: remove ~/.bun and related PATH entries")
    end

    :ok
  end

  @doc """
  Checks if required Rust targets are installed for a specific Tailwind version
  """
  def check_rust_targets_for_version(version) do
    required_targets = targets_for_version(version)
    installed_targets = get_installed_rust_targets()

    missing_targets =
      Enum.reject(required_targets, fn target ->
        target in installed_targets
      end)

    case missing_targets do
      [] -> {:ok, required_targets}
      missing -> {:error, missing}
    end
  end

  defp targets_for_version(version) do
    # For v4.x, always use platform-specific detection
    # v3.x doesn't need Rust targets
    default_targets(version)
  end

  defp default_targets(version) when is_binary(version) do
    cond do
      String.starts_with?(version, "4.") -> get_required_rust_targets()
      true -> []
    end
  end

  @doc """
  Gets list of installed Rust targets
  """
  def get_installed_rust_targets do
    case asdf_exec("rustup", ["target", "list", "--installed"]) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {_error, _} ->
        Logger.warning("Could not retrieve installed Rust targets")
        []
    end
  end

  @doc """
  Validates that all Rust targets for a version are available
  """
  def validate_rust_targets_for_version!(version) do
    case check_rust_targets_for_version(version) do
      {:ok, _targets} ->
        :ok

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
    case System.find_executable(program) do
      nil ->
        false

      _ ->
        # Running `--version` helps detect broken asdf shims with no version configured.
        case System.cmd(program, ["--version"]) do
          {_out, 0} -> true
          {_out, _code} -> false
        end
    end
  rescue
    ErlangError -> false
  end
end
