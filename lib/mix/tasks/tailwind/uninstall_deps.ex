defmodule Mix.Tasks.Tailwind.UninstallDeps do
  @moduledoc "Uninstalls all dependencies for building Tailwind CLI"
  use Mix.Task
  alias Defdo.TailwindBuilder.Dependencies

  @shortdoc "Uninstalls Tailwind CLI build dependencies"
  def run(_) do
    Mix.shell().info("Uninstalling Tailwind CLI build dependencies...")
    Dependencies.uninstall!()
    Mix.shell().info("✓ Dependencies uninstalled successfully")
  end
end
