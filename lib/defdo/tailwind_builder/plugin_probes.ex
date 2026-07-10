defmodule Defdo.TailwindBuilder.PluginProbes do
  @moduledoc """
  Functional probes for Tailwind plugins: a minimal input CSS + content class
  that a plugin must actually generate, plus the marker expected in the compiled
  output. Running a probe with a freshly-built standalone binary proves the
  plugin does not just install but *generates stable output* — this is the
  compatibility evidence recorded in the release manifest.

  A plugin with no registered probe is reported `:unverified` (someone must add a
  probe); a plugin whose probe does not produce its marker is a build failure
  (fail-closed), so a published binary always carries plugins proven to generate.
  """

  @type probe :: %{content: String.t(), expected: [String.t()]}

  # Package (npm name) => probe. `content` is placed in the scanned HTML; the
  # compiled, minified CSS must contain every string in `expected`.
  @probes %{
    "daisyui" => %{content: ~s(<button class="btn btn-primary">x</button>), expected: [".btn"]},
    "@tailwindcss/typography" => %{
      content: ~s(<article class="prose"><p>x</p></article>),
      expected: [".prose"]
    },
    "@tailwindcss/forms" => %{
      content: ~s(<input type="checkbox" class="form-checkbox" />),
      expected: [".form-checkbox"]
    },
    "@midudev/tailwind-animations" => %{
      content: ~s(<div class="animate-fade-in animate-duration-1000">x</div>),
      expected: ["animate-fade-in"]
    }
  }

  @doc "The probe for an npm package, or nil when none is registered."
  @spec probe_for(String.t()) :: probe() | nil
  def probe_for(package) when is_binary(package), do: Map.get(@probes, package)
  def probe_for(_), do: nil

  @doc "All packages that have a registered probe."
  @spec known_packages() :: [String.t()]
  def known_packages, do: Map.keys(@probes)

  @doc """
  The input CSS for a probe: import Tailwind and load the plugin under test.
  """
  @spec input_css(String.t()) :: String.t()
  def input_css(package), do: ~s(@import "tailwindcss";\n@plugin "#{package}";\n)
end
