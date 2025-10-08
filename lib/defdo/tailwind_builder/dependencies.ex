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
  @required_rust_targets ~w(wasm32-wasip1-threads)
  @tailwind_v4_requirements %{
    "4.0.0" => ["wasm32-wasip1-threads"],
    "4.1.0" => ["wasm32-wasip1-threads"],
    "4.1.11" => ["wasm32-wasip1-threads"]
  }

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
        - Rust (for cargo):
          asdf: asdf install rust latest && asdf set rust latest && asdf set --home rust latest
          manual: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        - Node.js (for npm):
          Ubuntu: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs
          macOS: brew install node
        - pnpm: npm install -g pnpm
        - Bun:
          asdf: asdf install bun latest && asdf set bun latest && asdf set --home bun latest
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
      is_installed?("asdf") ->
        Logger.info("Using asdf to install dependencies")

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

      is_installed?("brew") ->
        Logger.info("Using homebrew to install dependencies")
        System.cmd("brew", ["install", "node"], into: IO.stream())
        System.cmd("brew", ["install", "rust"], into: IO.stream())
        System.cmd("brew", ["install", "bun"], into: IO.stream())
        System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())

      true ->
        Logger.info("Using direct installation methods")

        System.cmd("curl", ["--proto", "=https", "--tlsv1.2", "-sSf", "https://sh.rustup.rs"],
          into: IO.stream()
        )

        System.cmd("curl", ["-o", "node.pkg", "https://nodejs.org/dist/latest/node-latest.pkg"],
          into: IO.stream()
        )

        System.cmd("sudo", ["installer", "-pkg", "node.pkg", "-target", "/"], into: IO.stream())
        System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())
        System.cmd("bash", ["-c", "curl -fsSL https://bun.sh/install | bash"], into: IO.stream())
        Logger.info("If bun is not available yet, add ~/.bun/bin to your PATH")
    end

    install_rust_targets!()
    :ok
  end

  @doc """
  Installs required Rust targets for TailwindCSS v4.x compilation
  """
  def install_rust_targets! do
    Logger.info("Installing required Rust targets...")

    results =
      for target <- @required_rust_targets do
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
    Map.get(@tailwind_v4_requirements, version, default_targets(version))
  end

  defp default_targets(version) when is_binary(version) do
    cond do
      String.starts_with?(version, "4.") -> @required_rust_targets
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
