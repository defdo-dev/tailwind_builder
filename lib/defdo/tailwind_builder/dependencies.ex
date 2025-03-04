defmodule Defdo.TailwindBuilder.Dependencies do
  @moduledoc """
  Manages build dependencies for TailwindBuilder
  """
  require Logger

  @required_tools ~w(npm pnpm node cargo)

  def check! do
    case missing_tools() do
      [] ->
        :ok

      missing ->
        raise """
        Missing required build tools: #{Enum.join(missing, ", ")}

        You can install them manually:
        - Rust (for cargo): curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        - Node.js (for npm): brew install node
        - pnpm: npm install -g pnpm

        Or run: mix tailwind.install_deps
        """
    end
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

        System.cmd("curl", ["-o", "node.pkg", "https://nodejs.org/dist/latest/node-latest.pkg"],
          into: IO.stream()
        )

        System.cmd("sudo", ["installer", "-pkg", "node.pkg", "-target", "/"], into: IO.stream())
        System.cmd("npm", ["install", "-g", "pnpm"], into: IO.stream())
    end

    :ok
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

  defp missing_tools do
    Enum.reject(@required_tools, &is_installed?/1)
  end

  defp is_installed?(program) do
    if System.find_executable("#{program}"), do: true, else: false
  end
end
