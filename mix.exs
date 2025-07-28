defmodule Defdo.TailwindBuilder.MixProject do
  use Mix.Project

  def project do
    [
      app: :tailwind_builder,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:castore, ">= 0.0.0"},
      {:mox, "~> 1.0"},
      {:mock, "~> 0.3", only: :test},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.20"},
      {:jason, "~> 1.4"},
      {:sweet_xml, "~> 0.7.4"}
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
