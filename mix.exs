defmodule Defdo.TailwindBuilder.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim()
  @organization "defdo"
  @source_url "https://github.com/defdo-dev/tailwind_builder"

  def project do
    [
      app: :tailwind_builder,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {Defdo.TailwindBuilder.Application, []}
    ]
  end

  defp description do
    "Builds custom Tailwind CLI + plugin (DaisyUI) standalone binaries and " <>
      "publishes versioned, checksum-verified release manifests."
  end

  defp package do
    [
      organization: @organization,
      files: ~w(lib CHANGELOG.md LICENSE.md mix.exs README.md VERSION),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: @version,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:castore, ">= 0.0.0"},
      {:mox, "~> 1.0"},
      {:mock, "~> 0.3", only: :test},
      {:req, "~> 0.6"},
      {:req_s3, "~> 0.2.4"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "tailwind.setup": [
        "tailwind.install_deps"
      ]
    ]
  end
end
