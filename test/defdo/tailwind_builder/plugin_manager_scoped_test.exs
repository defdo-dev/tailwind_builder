defmodule Defdo.TailwindBuilder.PluginManagerScopedTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.PluginManager

  # Minimal synthetic v4 standalone index.ts carrying the exact anchor strings
  # the patcher splits on. Enough to prove the emitted patches, not a real build.
  @index_ts """
    id = id.startsWith('tailwindcss/') ? id.slice(12) : id

    if (
      id.startsWith('@tailwindcss/') ||
      false
    ) {
      switch (id) {
        case 'tailwindcss':
          return require('@tailwindcss/aspect-ratio')
      }
    }

    let localModules = {
      'tailwindcss/defaultTheme.js': await import('tailwindcss/defaultTheme'),
    }
  """

  describe "scoped package names (e.g. @scope/pkg)" do
    setup do
      spec = %{"version" => ~s["@midudev/tailwind-animations": "0.2.0"]}
      {:ok, patched} = PluginManager.patch_file_content(@index_ts, spec, "index.ts", "4.1.11")
      %{patched: patched}
    end

    test "escapes the name inside emitted JS regex literals", %{patched: patched} do
      # "/" and "-" are escaped so the JS regex literal is not terminated early.
      assert patched =~ ~S[/(\/)?@midudev\/tailwind\-animations(\/.+)?$/]

      # A bare, unescaped occurrence inside a regex literal would be a corrupt
      # patch — there must be none.
      refute patched =~ ~S[/(\/)?@midudev/tailwind-animations(\/.+)?$/]
    end

    test "keeps the raw name in string-literal spots (require/import)", %{patched: patched} do
      assert patched =~ ~s[require('@midudev/tailwind-animations')]

      assert patched =~
               ~s['@midudev/tailwind-animations': await import('@midudev/tailwind-animations')]
    end

    test "startsWith guard uses the raw name", %{patched: patched} do
      assert patched =~ ~s[id.startsWith('@midudev/tailwind-animations')]
    end
  end

  test "unscoped names are unaffected by escaping" do
    spec = %{"version" => ~s["tailwindcss-animate": "1.0.7"]}
    {:ok, patched} = PluginManager.patch_file_content(@index_ts, spec, "index.ts", "4.1.11")

    # "-" is escaped in the regex spot; the require stays raw.
    assert patched =~ ~S[/(\/)?tailwindcss\-animate(\/.+)?$/]
    assert patched =~ ~s[require('tailwindcss-animate')]
  end
end
