defmodule Defdo.TailwindBuilder.PromoteTest do
  use ExUnit.Case, async: true

  alias Defdo.TailwindBuilder.Deployer

  test "promote_channel surfaces a source-manifest fetch failure without touching R2" do
    fetcher = fn _url -> {:error, :nope} end

    assert {:error, :nope} =
             Deployer.promote_channel(channel: "v4.3.2-rc1", fetcher: fetcher)
  end

  test "promote_channel rejects an unparseable source manifest" do
    fetcher = fn _url -> {:ok, "not-json"} end

    assert {:error, %Jason.DecodeError{}} =
             Deployer.promote_channel(channel: "v4.3.2-rc1", fetcher: fetcher)
  end
end
