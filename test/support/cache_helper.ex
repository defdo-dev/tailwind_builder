defmodule Defdo.TailwindBuilder.Test.CacheHelper do
  require Logger

  def with_cache(version, cache_key, fun) do
    cache_dir = Path.join(["/tmp", "tailwind_builder_test", "cache", "#{cache_key}-#{version}"])

    if File.exists?(cache_dir) do
      Logger.debug("Using cached result from #{cache_dir}")
      {:ok, %{cache_dir: cache_dir}}
    else
      case fun.() do
        {:ok, result} ->
          File.mkdir_p!(cache_dir)
          File.cp_r!(result.tailwind_standalone_root, cache_dir)
          {:ok, result}

        error ->
          error
      end
    end
  end
end
