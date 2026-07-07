defmodule Mix.Tasks.Tailwind.Promote do
  @shortdoc "Promote a published channel from the canary R2 prefix to production"
  @moduledoc """
  Promote an already-built, verified channel from one R2 prefix to another
  without rebuilding — the canary CI prefix to the production prefix by default.

      R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_HOST=... \\
        mix tailwind.promote --channel v4.3.2-rc1

  Options:
    * `--channel` (required) — e.g. `v4.3.2-rc1`
    * `--source-prefix` — default `tailwind_cli_daisyui_ci_canary`
    * `--dest-prefix` — default `tailwind_cli_daisyui`
    * `--bucket` — default `defdo`
    * `--storage-base-url` — default `https://storage.defdo.de`
  """
  use Mix.Task

  alias Defdo.TailwindBuilder.Deployer

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          channel: :string,
          source_prefix: :string,
          dest_prefix: :string,
          bucket: :string,
          storage_base_url: :string
        ]
      )

    channel = opts[:channel] || Mix.raise("--channel is required (e.g. v4.3.2-rc1)")

    Application.ensure_all_started(:req)
    configure_storage()

    promote_opts =
      [channel: channel]
      |> put_opt(:source_prefix, opts[:source_prefix])
      |> put_opt(:dest_prefix, opts[:dest_prefix])
      |> put_opt(:bucket, opts[:bucket])
      |> put_opt(:storage_base_url, opts[:storage_base_url])

    case Deployer.promote_channel(promote_opts) do
      {:ok, result} ->
        Mix.shell().info("Promoted #{result.promoted_files} files for #{channel}")
        Mix.shell().info("  Prod manifest: #{result.manifest_url}")

      {:error, reason} ->
        Mix.raise("Promotion failed: #{inspect(reason)}")
    end
  end

  defp put_opt(list, _key, nil), do: list
  defp put_opt(list, key, value), do: Keyword.put(list, key, value)

  defp configure_storage do
    Application.put_env(:tailwind_builder, :storage,
      access_key_id: env("R2_ACCESS_KEY_ID", "AWS_ACCESS_KEY_ID"),
      secret_access_key: env("R2_SECRET_ACCESS_KEY", "AWS_SECRET_ACCESS_KEY"),
      host: Deployer.normalize_storage_host(System.get_env("R2_HOST")),
      region: System.get_env("R2_REGION", System.get_env("AWS_REGION", "auto"))
    )
  end

  defp env(primary, fallback), do: System.get_env(primary) || System.get_env(fallback)
end
