defmodule Mix.Tasks.Tailwind.InstallDeps do
  @moduledoc "Installs all required dependencies for building Tailwind CLI"
  use Mix.Task
  alias Defdo.TailwindBuilder.Dependencies

  @shortdoc "Installs Tailwind CLI build dependencies"
  def run(_) do
    Mix.shell().info("Installing Tailwind CLI build dependencies...")
    Dependencies.install!()
    Mix.shell().info("✓ Dependencies installed successfully")
  end
end
