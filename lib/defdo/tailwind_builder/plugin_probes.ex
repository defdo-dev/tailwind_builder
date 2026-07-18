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

  @type load :: :plugin | :import
  @type probe :: %{
          required(:content) => String.t(),
          required(:expected) => [String.t()],
          required(:load) => load(),
          optional(:css_entry) => String.t()
        }

  # Package (npm name) => probe. `content` is placed in the scanned HTML; the
  # compiled, minified CSS must contain every string in `expected`.
  #
  # `load` selects how the plugin is loaded in the probe CSS:
  #   * `:plugin` (default) — a JS plugin: `@plugin "pkg"`.
  #   * `:import` — a CSS-first plugin (ships CSS, e.g. tw-animate-css): the CSS
  #     is pulled in with `@import "pkg"` instead of `@plugin`.
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
    "tailwind-animations" => %{
      content: ~s(<div class="animate-fade-in animate-duration-1000">x</div>),
      expected: ["animate-fade-in"],
      load: :import,
      css_entry: "src/index.css"
    },
    # tailwindcss-animate: JS plugin exposing `animate-in`/`fade-in-*` utilities.
    "tailwindcss-animate" => %{
      content: ~s(<div class="animate-in fade-in-0">x</div>),
      expected: ["animate-in"]
    },
    # tw-animate-css: CSS-first v4 port of tailwindcss-animate — loaded via
    # `@import`, not `@plugin`. Exposes `animate-in`/`fade-in-*` utilities.
    "tw-animate-css" => %{
      content: ~s(<div class="animate-in fade-in-0">x</div>),
      expected: ["animate-in"],
      load: :import,
      css_entry: "dist/tw-animate.css"
    }
  }

  @doc "The probe for an npm package, or nil when none is registered."
  @spec probe_for(String.t()) :: probe() | nil
  def probe_for(package) when is_binary(package), do: Map.get(@probes, package)
  def probe_for(_), do: nil

  @doc "Whether the package is a CSS-first plugin loaded with `@import`."
  @spec css_first?(String.t()) :: boolean()
  def css_first?(package) when is_binary(package) do
    match?(%{load: :import}, probe_for(package))
  end

  def css_first?(_), do: false

  @doc "The relative CSS entry shipped by a CSS-first package, or nil."
  @spec css_entry(String.t()) :: String.t() | nil
  def css_entry(package) when is_binary(package) do
    case probe_for(package) do
      %{load: :import, css_entry: css_entry} -> css_entry
      _ -> nil
    end
  end

  def css_entry(_), do: nil

  @doc "All packages that have a registered probe."
  @spec known_packages() :: [String.t()]
  def known_packages, do: Map.keys(@probes)

  @doc """
  The input CSS for a probe: import Tailwind and load the plugin under test.

  JS plugins load with `@plugin "pkg"`; CSS-first plugins (probe `load: :import`)
  load with `@import "pkg"`.
  """
  @spec input_css(String.t()) :: String.t()
  def input_css(package) do
    directive =
      case probe_for(package) do
        %{load: :import} -> ~s(@import "#{package}";)
        _ -> ~s(@plugin "#{package}";)
      end

    ~s(@import "tailwindcss";\n#{directive}\n)
  end
end
