defmodule Defdo.TailwindBuilder.BrowserPack do
  @moduledoc """
  Builds the `tailwind-browser-pack.mjs` artifact: a single self-contained ESM
  file that compiles Tailwind v4 CSS in a browser/worker, bundling the exact
  Tailwind version and plugin set the release compiles into the CLI.

  Pack contract v1 (frozen — consumers are built against exactly this):

    * Default export `{contract: 1, tailwindVersion, pluginSet, createCompiler}`.
    * `await createCompiler(themeSource)` returns `{build(candidates)}` where
      `candidates` is a string list and `build/1` returns the CSS string.
    * Worker-safe: no DOM/window access, no fetches, no top-level side effects.
    * Unknown `@import`/`@plugin` ids throw, naming the id and the bundled set.

  The pack is generated from the release's resolved plugin set — never from a
  hardcoded list — so the artifact always matches the CLI it ships with.
  """

  require Logger

  @pack_filename "tailwind-browser-pack.mjs"
  @contract 1
  @virtual_base "/tailwind-browser-pack"

  # `tailwindcss/index.css` re-exports the default stylesheet through RELATIVE
  # @imports (./theme.css, ./preflight.css, ./utilities.css), so the map must
  # answer both the package ids and their relative forms (resolved against the
  # virtual base).
  @tailwind_stylesheets [
    {"tailwindcss/index.css",
     ["tailwindcss", "tailwindcss/index", "tailwindcss/index.css", "./index.css"]},
    {"tailwindcss/theme.css", ["tailwindcss/theme", "tailwindcss/theme.css", "./theme.css"]},
    {"tailwindcss/preflight.css",
     ["tailwindcss/preflight", "tailwindcss/preflight.css", "./preflight.css"]},
    {"tailwindcss/utilities.css",
     ["tailwindcss/utilities", "tailwindcss/utilities.css", "./utilities.css"]}
  ]

  @type plugin_spec :: %{name: String.t(), version: String.t(), plugin_key: String.t() | nil}
  @type inputs :: %{
          js_modules: [%{id: String.t(), import: String.t(), aliases: [String.t()]}],
          stylesheets: [%{id: String.t(), import: String.t(), aliases: [String.t()]}]
        }

  @doc "The published artifact filename."
  def pack_filename, do: @pack_filename

  @doc "The frozen pack contract version."
  def contract, do: @contract

  @doc """
  Resolve a release plugin set (the manifest's `plugin_set` shape) into the
  pack's bundling inputs. CSS-first plugins become text stylesheets, JS
  plugins become modules. Unknown plugin keys are rejected — a pack that
  silently dropped a plugin would produce wrong CSS downstream.
  """
  @spec resolve_inputs([plugin_spec()]) ::
          {:ok, inputs()} | {:error, {:unsupported_pack_plugin, String.t() | nil}}
  def resolve_inputs(plugin_set) when is_list(plugin_set) do
    plugin_set
    |> Enum.reduce_while({:ok, %{js_modules: [], stylesheets: []}}, fn plugin, {:ok, acc} ->
      case plugin_inputs(plugin) do
        {:ok, %{js_modules: mods, stylesheets: sheets}} ->
          {:cont,
           {:ok,
            %{
              js_modules: acc.js_modules ++ mods,
              stylesheets: acc.stylesheets ++ sheets
            }}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp plugin_inputs(%{plugin_key: "daisyui_v5"}) do
    {:ok,
     %{
       js_modules: [
         %{id: "daisyui", import: "daisyui", aliases: []},
         %{
           id: "daisyui/theme",
           import: "daisyui/theme/index.js",
           aliases: ["daisyui/theme/index.js"]
         }
       ],
       stylesheets: []
     }}
  end

  defp plugin_inputs(%{plugin_key: "tw_animate_css"}) do
    # tw-animate-css only exposes its entry behind the `style` export
    # condition, which esbuild does not enable (enabling it globally would flip
    # `tailwindcss` itself to its stylesheet entry), so it is bundled by its
    # relative vendored path — bypassing the package exports map.
    {:ok,
     %{
       js_modules: [],
       stylesheets: [
         %{
           id: "tw-animate-css",
           import: "./node_modules/tw-animate-css/dist/tw-animate.css",
           aliases: ["tw-animate-css/dist/tw-animate.css"]
         }
       ]
     }}
  end

  defp plugin_inputs(%{plugin_key: "tailwind_animations"}) do
    {:ok,
     %{
       js_modules: [],
       stylesheets: [
         %{
           id: "tailwind-animations",
           import: "tailwind-animations/index.css",
           aliases: ["tailwind-animations/index.css"]
         }
       ]
     }}
  end

  defp plugin_inputs(%{plugin_key: key}), do: {:error, {:unsupported_pack_plugin, key}}
  defp plugin_inputs(_other), do: {:error, {:unsupported_pack_plugin, nil}}

  @doc """
  Render the pack entry module (pre-bundle) for the given Tailwind version and
  plugin set. Exposed for review and tests; `build/2` writes it next to the
  standalone package before invoking esbuild.
  """
  @spec render_entry(String.t(), [plugin_spec()]) :: {:ok, String.t()} | {:error, term()}
  def render_entry(tailwind_version, plugin_set) do
    with {:ok, inputs} <- resolve_inputs(plugin_set) do
      {:ok,
       """
       // Generated by tailwind_builder BrowserPack (contract #{@contract}). Do not edit.
       import { compile } from "tailwindcss"
       #{render_tailwind_stylesheet_imports()}
       #{render_imports(inputs.stylesheets, :css)}
       #{render_imports(inputs.js_modules, :js)}

       const VIRTUAL_BASE = "#{@virtual_base}"

       const STYLESHEETS = new Map([
       #{render_stylesheet_map(inputs.stylesheets)}
       ])

       const MODULES = new Map([
       #{render_module_map(inputs.js_modules)}
       ])

       function knownIds(map) {
         return [...map.keys()].join(", ")
       }

       async function loadStylesheet(id, base) {
         const content = STYLESHEETS.get(id)

         if (content === undefined) {
           throw new Error(
             `Unknown stylesheet "${id}" (imported from ${base}). ` +
               `This Tailwind browser pack only bundles: ${knownIds(STYLESHEETS)}.`,
           )
         }

         return { path: id, base: VIRTUAL_BASE, content }
       }

       async function loadModule(id, base) {
         const module = MODULES.get(id)

         if (module === undefined) {
           throw new Error(
             `Unknown module "${id}" (loaded from ${base}). ` +
               `This Tailwind browser pack only bundles: ${knownIds(MODULES)}.`,
           )
         }

         return { path: id, base: VIRTUAL_BASE, module }
       }

       const tailwindVersion = #{inspect(tailwind_version)}
       const pluginSet = #{render_plugin_set(plugin_set)}

       export default {
         contract: #{@contract},
         tailwindVersion,
         pluginSet,
         createCompiler: async (themeSource) => {
           const compiler = await compile(themeSource, {
             base: VIRTUAL_BASE,
             loadStylesheet,
             loadModule,
           })

           return { build: (candidates) => compiler.build(candidates) }
         },
       }
       """}
    end
  end

  defp render_tailwind_stylesheet_imports do
    @tailwind_stylesheets
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {{import_path, _ids}, idx} ->
      ~s|import tailwindCss#{idx} from "#{import_path}"|
    end)
  end

  defp render_imports(entries, kind) do
    entries
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {entry, idx} ->
      ~s|import #{kind}#{idx} from "#{entry.import}"|
    end)
  end

  defp render_stylesheet_map(plugin_sheets) do
    all =
      (@tailwind_stylesheets
       |> Enum.with_index()
       |> Enum.map(fn {{_path, ids}, idx} -> {ids, "tailwindCss#{idx}"} end)) ++
        (plugin_sheets
         |> Enum.with_index()
         |> Enum.map(fn {%{id: id, aliases: aliases}, idx} -> {[id] ++ aliases, "css#{idx}"} end))

    all
    |> Enum.flat_map(fn {ids, var} -> Enum.map(ids, &{&1, var}) end)
    |> Enum.map_join("\n", fn {id, var} -> "  [" <> inspect(id) <> ", " <> var <> "]," end)
  end

  defp render_module_map(js_modules) do
    js_modules
    |> Enum.with_index()
    |> Enum.flat_map(fn {%{id: id, aliases: aliases}, idx} ->
      Enum.map([id] ++ aliases, &{&1, "js#{idx}"})
    end)
    |> Enum.map_join("\n", fn {id, var} -> "  [" <> inspect(id) <> ", " <> var <> "]," end)
  end

  defp render_plugin_set(plugin_set) do
    entries =
      Enum.map_join(plugin_set, ", ", fn plugin ->
        ~s|{ name: #{inspect(plugin.name)}, version: #{inspect(plugin.version)}, plugin_key: #{inspect(plugin.plugin_key)} }|
      end)

    "[#{entries}]"
  end

  @doc """
  Build the pack into the standalone dist directory. Expects the release
  source tree (plugins already installed by the release's plugin step).
  Returns `{:ok, pack_metadata}` with the local path and checksum.
  """
  @spec build(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(source_path, opts) do
    version = Keyword.fetch!(opts, :version)
    plugin_set = Keyword.fetch!(opts, :plugin_set)
    tailwind_version = Keyword.get(opts, :tailwind_version, version)

    standalone_dir =
      Path.join([source_path, "tailwindcss-#{version}", "packages", "@tailwindcss-standalone"])

    dist_dir = Path.join(standalone_dir, "dist")
    entry_path = Path.join(standalone_dir, "tailwind_browser_pack.entry.mjs")
    pack_path = Path.join(dist_dir, @pack_filename)

    with :ok <- require_dir(standalone_dir),
         {:ok, entry} <- render_entry(tailwind_version, plugin_set),
         :ok <- File.write(entry_path, entry),
         :ok <- File.mkdir_p(dist_dir),
         {:ok, esbuild} <- esbuild_bin(source_path, version),
         :ok <- run_esbuild(esbuild, entry_path, pack_path) do
      File.rm(entry_path)

      {:ok,
       %{
         filename: @pack_filename,
         contract: @contract,
         local_path: pack_path,
         sha256: sha256_file(pack_path),
         size_bytes: File.stat!(pack_path).size,
         tailwind_version: tailwind_version,
         plugin_set: plugin_set
       }}
    else
      {:error, reason} ->
        File.rm(entry_path)
        {:error, reason}
    end
  end

  defp require_dir(path) do
    if File.dir?(path), do: :ok, else: {:error, {:standalone_dir_not_found, path}}
  end

  defp esbuild_bin(source_path, version) do
    local =
      Path.join([source_path, "tailwindcss-#{version}", "node_modules", ".bin", "esbuild"])

    cond do
      File.exists?(local) -> {:ok, local}
      executable?("esbuild") -> {:ok, "esbuild"}
      true -> {:error, :esbuild_not_found}
    end
  end

  defp executable?(name) do
    case System.cmd("which", [name], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp run_esbuild(esbuild, entry_path, pack_path) do
    args = [
      entry_path,
      "--bundle",
      "--format=esm",
      "--platform=browser",
      "--target=es2022",
      "--loader:.css=text",
      "--outfile=#{pack_path}"
    ]

    case System.cmd(esbuild, args, stderr_to_stdout: true) do
      {output, 0} ->
        Logger.debug("esbuild browser pack: #{output}")
        :ok

      {output, status} ->
        {:error, {:esbuild_failed, status, output}}
    end
  end

  @doc """
  Smoke-test a built pack under node: create a compiler with
  `@import "tailwindcss"; @plugin "daisyui";`, build a candidate list, and
  return the produced CSS. The caller asserts on the output (the release
  checks `.btn` and the daisyUI version banner).
  """
  @spec smoke_test(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def smoke_test(pack_path, opts \\ []) do
    harness = Keyword.get(opts, :harness, smoke_harness_path())
    node = Keyword.get(opts, :node, "node")

    unless File.exists?(pack_path) do
      throw({:error, {:pack_not_found, pack_path}})
    end

    case System.cmd(node, [harness, pack_path], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {:pack_smoke_failed, status, output}}
    end
  rescue
    error -> {:error, error}
  end

  defp smoke_harness_path do
    Path.join(:code.priv_dir(:tailwind_builder), "browser_pack/smoke.mjs")
  end

  @doc """
  Verify smoke output: the daisyUI banner names the exact bundled version and
  the candidate `.btn` produced a rule.
  """
  @spec verify_smoke_output(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def verify_smoke_output(css, daisyui_version) do
    cond do
      not String.contains?(css, ".btn") ->
        {:error, {:pack_smoke_missing_rule, ".btn"}}

      is_binary(daisyui_version) and not String.contains?(css, "daisyUI #{daisyui_version}") ->
        {:error, {:pack_smoke_missing_banner, daisyui_version}}

      true ->
        :ok
    end
  end

  defp sha256_file(path) do
    :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
  end
end
