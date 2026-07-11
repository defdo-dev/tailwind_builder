defmodule Defdo.TailwindBuilder.BuilderOptionsTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Builder

  test "compile accepts a per-command timeout" do
    result =
      Builder.compile(
        version: "3.4.0",
        source_path: "/path/that/does/not/exist",
        validate_tools: false,
        timeout: 1_800_000
      )

    assert {:error, _reason} = result
    refute inspect(result) =~ "unknown keys"
  end
end
