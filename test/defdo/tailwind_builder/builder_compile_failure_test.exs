defmodule Defdo.TailwindBuilder.BuilderCompileFailureTest do
  @moduledoc """
  A failed compilation must abort the pipeline, not report success.

  `Builder.compile/1` used to return `{:ok, result}` when the build had failed. The `with` clause
  read:

      {:compile, compilation_result} <-
        {:compile, execute_compilation_with_telemetry(version, paths, debug, timeout)}

  which matches **any** term — `{:error, reason}` included — so the failure walked straight into
  the success branch and the `{step, error}` handler below was unreachable code.

  Observed during a real 4.3.3 build attempt: the log printed
  `Compilation result: {:error, {:"pnpm install", ...}}` and the pipeline still advanced into
  `Deployer.deploy`. It stopped only later, and only because `dist/` happened not to exist. On a
  builder that reuses a deterministic temp path across runs — which the native macOS builder does
  — a stale `dist/` from an earlier build would have been found there, checksummed, smoke-tested
  and published as though freshly built. Silent, and signed.

  The existing `builder_options_test` cannot catch this: it passes a path that does not exist, so
  it fails at `validate_paths` and never reaches the compile step. This one builds a tree that
  *passes* validation and then fails to compile, which is the only way through to the clause under
  test.
  """
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Builder

  @version "3.4.0"

  # `validate_paths_exist/1` only requires the directories to be there. Creating them and nothing
  # else means path validation passes and the build genuinely fails — no stubbing, no injected
  # error, the real failure the real pipeline would hit.
  defp source_tree(tmp_dir) do
    standalone = Path.join([tmp_dir, "tailwindcss-#{@version}", "standalone-cli"])
    File.mkdir_p!(standalone)
    tmp_dir
  end

  @tag :tmp_dir
  test "a failed compilation returns an error, not {:ok, ...}", %{tmp_dir: tmp_dir} do
    result =
      Builder.compile(
        version: @version,
        source_path: source_tree(tmp_dir),
        validate_tools: false,
        timeout: 30_000
      )

    assert {:error, _reason} = result,
           "compile/1 reported success for a build that produced nothing: #{inspect(result)}"
  end

  @tag :tmp_dir
  test "the error names the step that failed", %{tmp_dir: tmp_dir} do
    # The `{step, error}` branch exists to say where it broke, and was dead code. If it is alive
    # again, the step reaches the caller.
    {:error, reason} =
      Builder.compile(
        version: @version,
        source_path: source_tree(tmp_dir),
        validate_tools: false,
        timeout: 30_000
      )

    assert match?({:compile, _}, reason) or match?({:validate_paths, _}, reason),
           "expected the failing step to be named, got: #{inspect(reason)}"
  end

  @tag :tmp_dir
  test "no dist/ is produced, so nothing downstream could have been published",
       %{tmp_dir: tmp_dir} do
    # The scenario that made this dangerous rather than merely wrong: had `dist/` been populated
    # by an earlier run, the old code would have shipped it.
    source_tree(tmp_dir)

    Builder.compile(
      version: @version,
      source_path: source_tree(tmp_dir),
      validate_tools: false,
      timeout: 30_000
    )

    dist = Path.join([tmp_dir, "tailwindcss-#{@version}", "standalone-cli", "dist"])

    refute File.dir?(dist) and File.ls!(dist) != [],
           "a failed build left artifacts at #{dist}; those are what would have been published"
  end
end
