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
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  # `mix precommit` ends in `mix test`, so the whole alias must run in :test.
  def cli do
    [preferred_envs: [precommit: :test]]
  end

  # test/support holds helper MODULES (.ex), not test files: compile them as
  # sources so `mix test` stops reporting them as unmatched test files.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      files: ~w(lib priv CHANGELOG.md LICENSE.md mix.exs README.md VERSION),
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
      {:mock, "~> 0.3", only: :test},
      {:req, "~> 0.7"},
      {:defdo_s3, "~> 0.2", organization: @organization},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "tailwind.setup": [
        "tailwind.install_deps"
      ],
      # Point git at the tracked hooks dir so the pre-commit (format + credo) runs.
      "hooks.install": ["cmd git config core.hooksPath .githooks"],
      # Full-tree gate for CI or a manual pre-push check.
      check: ["format --check-formatted", "credo --strict"],
      # The gate CI runs, same name as in tailwind_builder_hub and
      # tailwind_builder_worker so one command works across the ecosystem.
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "test"
      ]
    ]
  end
end
