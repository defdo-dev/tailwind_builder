defmodule Defdo.TailwindBuilder.PluginProbesTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.{Deployer, PluginProbes}

  test "probe_for returns a probe for known packages, nil otherwise" do
    assert %{expected: [".btn"]} = PluginProbes.probe_for("daisyui")
    assert %{expected: [".prose"]} = PluginProbes.probe_for("@tailwindcss/typography")
    assert PluginProbes.probe_for("totally-unknown-plugin") == nil
  end

  test "input_css imports tailwind and loads the plugin" do
    css = PluginProbes.input_css("daisyui")
    assert css =~ ~s(@import "tailwindcss")
    assert css =~ ~s(@plugin "daisyui")
  end

  test "input_css loads a CSS-first plugin with @import, not @plugin" do
    css = PluginProbes.input_css("tw-animate-css")
    assert css =~ ~s(@import "tailwindcss")
    assert css =~ ~s(@import "tw-animate-css")
    refute css =~ ~s(@plugin "tw-animate-css")
  end

  test "probes cover the animation plugins" do
    assert %{expected: ["animate-in"], load: :import, css_entry: "dist/tw-animate.css"} =
             PluginProbes.probe_for("tw-animate-css")

    assert %{expected: ["animate-fade-in"], load: :import, css_entry: "src/index.css"} =
             PluginProbes.probe_for("tailwind-animations")

    assert %{expected: ["animate-in"]} = PluginProbes.probe_for("tailwindcss-animate")

    assert PluginProbes.css_first?("tw-animate-css")
    assert PluginProbes.css_entry("tw-animate-css") == "dist/tw-animate.css"
    refute PluginProbes.css_first?("daisyui")
    assert PluginProbes.css_entry("daisyui") == nil
  end

  test "plugin_packages extracts npm names from mixed plugin_set shapes" do
    plugin_set = [
      %{name: "daisyui", version: "5.6.10", plugin_key: "daisyui_v5"},
      %{"name" => "@tailwindcss/forms", "version" => "0.5.9"},
      "typography=@tailwindcss/typography@0.5.10",
      "daisyui@5.6.10"
    ]

    packages = Deployer.plugin_packages(plugin_set)

    assert "daisyui" in packages
    assert "@tailwindcss/forms" in packages
    assert "@tailwindcss/typography" in packages
    # de-duplicated
    assert Enum.count(packages, &(&1 == "daisyui")) == 1
  end

  test "smoke_test_plugins reports :unverified for packages without a probe" do
    # No binary is executed for an unverified package.
    assert [%{plugin: "mystery-plugin", status: :unverified}] =
             Deployer.smoke_test_plugins("/nonexistent/binary", ["mystery-plugin"])
  end
end
