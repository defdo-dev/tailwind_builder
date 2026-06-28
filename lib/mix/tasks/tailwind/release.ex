defmodule Mix.Tasks.Tailwind.Release do
  @moduledoc """
  Build and publish a Tailwind standalone release candidate.

  Defaults to Tailwind 4.2.2 with DaisyUI 5.5.19 and release channel v4.2.2-rc1.

  ## Options

    * `--verify-upload` — after upload, fetch each artifact from
      `--storage-base-url`, validate its sha256, and abort before publishing
      `manifest.json`/`sha256sums.txt` if any artifact fails verification.
    * `--verify-smoke-test` — additionally smoke test each downloaded artifact
      during verification (requires `--verify-upload`).
    * `--dry-run` — run all local steps and produce manifest/checksum output
      without uploading anything to storage.
    * `--overwrite-policy fail|overwrite|promote_only` — control rerun behavior
      against artifacts already published to storage.
  """

  use Mix.Task

  alias Defdo.TailwindBuilder.ConfigProviders.{
    DevelopmentConfigProvider,
    ProductionConfigProvider,
    StagingConfigProvider,
    TestingConfigProvider
  }

  alias Defdo.TailwindBuilder.{Deployer, Release}

  @shortdoc "Build and publish a Tailwind release"

  @config_providers %{
    "development" => DevelopmentConfigProvider,
    "production" => ProductionConfigProvider,
    "staging" => StagingConfigProvider,
    "testing" => TestingConfigProvider
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          version: :string,
          channel: :string,
          source_path: :string,
          bucket: :string,
          prefix: :string,
          storage_base_url: :string,
          destination: :string,
          config_provider: :string,
          plugin: :keep,
          debug: :boolean,
          smoke_test: :boolean,
          verify_upload: :boolean,
          verify_smoke_test: :boolean,
          dry_run: :boolean,
          overwrite_policy: :string
        ],
        aliases: [
          v: :version,
          c: :channel,
          s: :source_path,
          b: :bucket,
          p: :plugin,
          d: :destination
        ]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    plugins =
      case Keyword.get_values(opts, :plugin) do
        [] -> ["daisyui_v5"]
        values -> values
      end

    destination =
      opts
      |> Keyword.get(:destination, "r2")
      |> parse_destination()

    storage_base_url =
      Keyword.get(
        opts,
        :storage_base_url,
        System.get_env("TAILWIND_STORAGE_BASE_URL", "https://storage.defdo.de")
      )

    dry_run = Keyword.get(opts, :dry_run, false)

    unless dry_run do
      maybe_put_storage_config(destination)
    end

    release_opts =
      [
        version: Keyword.get(opts, :version, "4.2.2"),
        release_channel: Keyword.get(opts, :channel, "v4.2.2-rc1"),
        source_path: Keyword.get(opts, :source_path),
        bucket: Keyword.get(opts, :bucket, System.get_env("TAILWIND_R2_BUCKET", "defdo")),
        prefix:
          Keyword.get(opts, :prefix, System.get_env("TAILWIND_R2_PREFIX", "tailwind_cli_daisyui")),
        storage_base_url: storage_base_url,
        destination: destination,
        config_provider: parse_config_provider(Keyword.get(opts, :config_provider)),
        plugins: plugins,
        debug: Keyword.get(opts, :debug, false),
        smoke_test_binaries: Keyword.get(opts, :smoke_test, true),
        verify_upload: Keyword.get(opts, :verify_upload, false),
        verify_smoke_test: Keyword.get(opts, :verify_smoke_test, false),
        dry_run: dry_run,
        overwrite_policy: parse_overwrite_policy(Keyword.get(opts, :overwrite_policy))
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Release.run(release_opts) do
      {:ok, result} ->
        if Map.get(result, :dry_run, false) do
          Mix.shell().info("Release completed successfully (dry run — nothing uploaded)")
        else
          Mix.shell().info("Release completed successfully")
        end

        Mix.shell().info("  Version: #{result.version}")
        Mix.shell().info("  Channel: #{result.release_channel}")
        Mix.shell().info("  Source path: #{result.source_path}")
        Mix.shell().info("  Deployed binaries: #{result.deploy.binaries_deployed}")

        if is_binary(result.deploy.sha256sums) do
          Mix.shell().info("  Checksums generated: yes")
        end

        if is_map(result.deploy.manifest) do
          Mix.shell().info("  Manifest generated: yes")
        end

      {:error, reason} ->
        Mix.raise("Release failed: #{inspect(reason)}")
    end
  end

  defp parse_destination("r2"), do: :r2
  defp parse_destination("s3"), do: :s3
  defp parse_destination(other), do: Mix.raise("Unsupported destination: #{other}")

  defp parse_overwrite_policy(nil), do: nil
  defp parse_overwrite_policy("fail"), do: :fail
  defp parse_overwrite_policy("overwrite"), do: :overwrite
  defp parse_overwrite_policy("promote_only"), do: :promote_only

  defp parse_overwrite_policy(other) do
    Mix.raise(
      "Unsupported overwrite policy: #{other}. Expected one of: fail, overwrite, promote_only"
    )
  end

  defp parse_config_provider(nil), do: ProductionConfigProvider

  defp parse_config_provider(provider_name) when is_binary(provider_name) do
    normalized_name = String.downcase(provider_name)

    case Map.get(@config_providers, normalized_name) do
      nil ->
        Mix.raise(
          "Unsupported config provider: #{provider_name}. Expected one of: #{Enum.join(Map.keys(@config_providers), ", ")}"
        )

      provider ->
        provider
    end
  end

  defp maybe_put_storage_config(destination) when destination in [:r2, :s3] do
    case Application.get_env(:tailwind_builder, :storage) do
      storage when is_list(storage) and storage != [] ->
        :ok

      _ ->
        storage_config = %{
          access_key_id: env_or_fallback("R2_ACCESS_KEY_ID", "AWS_ACCESS_KEY_ID"),
          secret_access_key: env_or_fallback("R2_SECRET_ACCESS_KEY", "AWS_SECRET_ACCESS_KEY"),
          host: Deployer.normalize_storage_host(System.get_env("R2_HOST")),
          region: System.get_env("R2_REGION", System.get_env("AWS_REGION", "auto"))
        }

        missing =
          storage_config
          |> Enum.filter(fn {_key, value} -> is_nil(value) end)
          |> Enum.map(fn {key, _value} -> key end)

        if missing != [] do
          Mix.raise(
            "Missing R2 configuration for #{destination}: #{Enum.join(Enum.map(missing, &to_string/1), ", ")}. Set R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_HOST, and optionally R2_REGION."
          )
        end

        Application.put_env(:tailwind_builder, :storage, Map.to_list(storage_config))
    end
  end

  defp env_or_fallback(primary, fallback) do
    System.get_env(primary) || System.get_env(fallback)
  end
end
