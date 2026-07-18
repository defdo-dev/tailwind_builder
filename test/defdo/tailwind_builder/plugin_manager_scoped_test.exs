defmodule Defdo.TailwindBuilder.PluginManagerScopedTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.PluginManager

  @standalone_fixture Path.expand(
                        "../../support/fixtures/standalone_index_v4.3.2.ts",
                        __DIR__
                      )

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

  test "embeds CSS-first plugins as files without JS module patches" do
    index_ts = File.read!(@standalone_fixture)
    spec = %{"version" => ~s["tw-animate-css": "1.4.0"]}
    {:ok, patched} = PluginManager.patch_file_content(index_ts, spec, "index.ts", "4.3.2")

    assert patched =~
             "import twAnimateCss from '../node_modules/tw-animate-css/dist/tw-animate.css' with { type: 'file' }"

    assert patched =~ "return localResolve(twAnimateCss)"
    assert patched =~ "id.startsWith('tw-animate-css') ||"
    refute patched =~ "await import('tw-animate-css')"
    refute patched =~ "require('tw-animate-css')"

    # The embedded import must be its own statement, not glued onto the
    # preceding `utilitiesCss` import (no newline == a JS syntax error).
    refute patched =~ "with { type: 'file' }import twAnimateCss"
    assert patched =~ "with { type: 'file' }\nimport twAnimateCss"

    # The id guard must be a valid regex literal: the `/` separators inside it
    # have to be escaped (`\/`), otherwise the literal terminates early.
    assert patched =~ ~S[/(\/)?tw\-animate\-css(\/.+)?$/.test(id)]
    refute patched =~ "/(/)?tw"
  end

  test "keeps the JS plugin path for daisyui" do
    index_ts = File.read!(@standalone_fixture)
    spec = %{"version" => ~s["daisyui": "5.6.16"]}
    {:ok, patched} = PluginManager.patch_file_content(index_ts, spec, "index.ts", "4.3.2")

    assert patched =~ "await import('daisyui')"
    assert patched =~ "return require('daisyui')"
  end
end
