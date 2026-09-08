defmodule Defdo.TailwindBuilder.BrowserPackTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.BrowserPack

  @catalog [
    %{name: "daisyui", version: "5.7.4", plugin_key: "daisyui_v5"},
    %{name: "tailwind-animations", version: "1.0.1", plugin_key: "tailwind_animations"},
    %{name: "tw-animate-css", version: "1.4.0", plugin_key: "tw_animate_css"}
  ]

  describe "resolve_inputs/1" do
    test "maps the release catalog into js modules and css-first stylesheets" do
      assert {:ok, inputs} = BrowserPack.resolve_inputs(@catalog)

      assert [%{id: "daisyui", import: "daisyui"}, %{id: "daisyui/theme"}] = inputs.js_modules

      assert [%{id: "tailwind-animations"}, %{id: "tw-animate-css"}] =
               Enum.sort_by(inputs.stylesheets, & &1.id)
    end

    test "tw-animate-css bundles by its relative vendored path (exports map only exposes `style`)" do
      assert {:ok, inputs} = BrowserPack.resolve_inputs(@catalog)
      tw = Enum.find(inputs.stylesheets, &(&1.id == "tw-animate-css"))
      assert tw.import == "./node_modules/tw-animate-css/dist/tw-animate.css"
      assert "tw-animate-css/dist/tw-animate.css" in tw.aliases
    end

    test "unknown plugin keys are rejected, never silently dropped" do
      assert {:error, {:unsupported_pack_plugin, "mystery"}} =
               BrowserPack.resolve_inputs([%{name: "m", version: "1", plugin_key: "mystery"}])

      assert {:error, {:unsupported_pack_plugin, nil}} =
               BrowserPack.resolve_inputs([%{name: "m", version: "1", plugin_key: nil}])
    end
  end

  describe "render_entry/2" do
    test "emits the frozen contract v1 shape with recipe-driven versions" do
      assert {:ok, entry} = BrowserPack.render_entry("4.3.3", @catalog)

      assert entry =~ "contract: 1"
      assert entry =~ ~s|const tailwindVersion = "4.3.3"|
      assert entry =~ ~s|{ name: "daisyui", version: "5.7.4", plugin_key: "daisyui_v5" }|
      assert entry =~ "createCompiler: async (themeSource)"
      assert entry =~ "build: (candidates) => compiler.build(candidates)"
    end

    test "bundles every id the theme can reference, including relative css ids" do
      assert {:ok, entry} = BrowserPack.render_entry("4.3.3", @catalog)

      for id <- [
            "tailwindcss",
            "tailwindcss/index.css",
            "./theme.css",
            "./preflight.css",
            "./utilities.css",
            "tw-animate-css",
            "tailwind-animations",
            "daisyui",
            "daisyui/theme"
          ] do
        assert entry =~ ~s|["#{id}",|, "missing stylesheet/module id #{id}"
      end
    end

    test "unknown ids throw naming the id and the bundled set" do
      assert {:ok, entry} = BrowserPack.render_entry("4.3.3", @catalog)

      assert entry =~ ~s|Unknown stylesheet "${id}"|
      assert entry =~ ~s|Unknown module "${id}"|
      assert entry =~ "only bundles"
    end

    test "rejects an unsupported plugin instead of emitting a half-bundled pack" do
      assert {:error, {:unsupported_pack_plugin, "mystery"}} =
               BrowserPack.render_entry("4.3.3", [
                 %{name: "m", version: "1.0.0", plugin_key: "mystery"}
               ])
    end
  end

  describe "verify_smoke_output/2" do
    @daisyui [%{name: "daisyui", version: "5.7.4", plugin_key: "daisyui_v5"}]
    @animate [%{name: "tw-animate-css", version: "1.4.0", plugin_key: "tw_animate_css"}]

    test "passes with the core rule, .btn rules and the exact daisyUI banner" do
      css = "/*! 🌼 daisyUI 5.7.4 */\n.underline{x}\n.btn{x}"

      assert :ok = BrowserPack.verify_smoke_output(css, @daisyui)
    end

    test "fails without .btn rules when daisyUI is in the pack" do
      assert {:error, {:pack_smoke_missing_rule, ".btn"}} =
               BrowserPack.verify_smoke_output(".underline{x} daisyUI 5.7.4", @daisyui)
    end

    test "fails on a version-mismatched banner" do
      assert {:error, {:pack_smoke_missing_banner, "5.7.4"}} =
               BrowserPack.verify_smoke_output(".underline{x} .btn{x} daisyUI 5.6.18", @daisyui)
    end

    test "a pack without daisyUI is not asked for .btn" do
      assert :ok = BrowserPack.verify_smoke_output(".underline{x}", [])
    end

    test "still requires the core rule, whatever the plugin set" do
      assert {:error, {:pack_smoke_missing_rule, ".underline"}} =
               BrowserPack.verify_smoke_output(".btn{x}", [])
    end

    test "each bundled plugin adds its own marker" do
      assert {:error, {:pack_smoke_missing_rule, ".animate-in"}} =
               BrowserPack.verify_smoke_output(".underline{x}", @animate)

      assert :ok = BrowserPack.verify_smoke_output(".underline{x} .animate-in{x}", @animate)
    end

    test "reads plugin entries with string keys too" do
      string_keyed = [%{"name" => "daisyui", "version" => "5.7.4", "plugin_key" => "daisyui_v5"}]
      css = ".underline{x} .btn{x} daisyUI 5.7.4"

      assert :ok = BrowserPack.verify_smoke_output(css, string_keyed)
    end
  end
end
