defmodule Defdo.TailwindBuilder.Deployer do
  @moduledoc """
  Specialized module for distributing compiled binaries with comprehensive telemetry.

  Responsibilities:
  - Upload binaries to different destinations (S3, R2, etc.) with performance tracking
  - Validate binaries before distribution
  - Handle version metadata
  - Generate distribution manifests
  - Monitor deployment performance and success rates

  Does not handle compilation or download, only final distribution.
  """

  require Logger
  alias Defdo.TailwindBuilder.{Core, Telemetry}

  @doc """
  Deploy compiled binaries to a destination with comprehensive telemetry tracking
  """
  def deploy(opts \\ []) do
    # Use telemetry wrapper for comprehensive tracking
    target = determine_target_from_opts(opts)

    Telemetry.track_deploy(target, fn ->
      do_deploy(opts)
    end)
  end

  # Helper function to determine deployment target from options
  defp determine_target_from_opts(opts) do
    cond do
      # S3 or R2 based on bucket
      opts[:bucket] -> :cloud
      opts[:destination] && String.starts_with?(opts[:destination], "/") -> :local
      true -> :unknown
    end
  end

  defp do_deploy(opts) do
    opts =
      Keyword.validate!(opts, [
        :version,
        :source_path,
        :destination,
        :bucket,
        :prefix,
        :validate_binaries,
        :generate_manifest
      ])

    version = opts[:version] || raise ArgumentError, "version is required"
    source_path = opts[:source_path] || raise ArgumentError, "source_path is required"
    destination = opts[:destination] || :r2
    validate_binaries = Keyword.get(opts, :validate_binaries, true)
    generate_manifest = Keyword.get(opts, :generate_manifest, true)

    with {:find_binaries, {:ok, binaries}} <-
           {:find_binaries, find_distributable_binaries(source_path, version)},
         {:filter_binaries, {:ok, binaries}} <-
           {:filter_binaries, filter_binaries_for_deploy(binaries, version)},
         {:validate, :ok} <- {:validate, maybe_validate_binaries(binaries, validate_binaries)},
         {:deploy_binaries, {:ok, deployed}} <-
           {:deploy_binaries, deploy_binaries(binaries, destination, opts)},
         {:manifest, {:ok, manifest}} <-
           {:manifest, maybe_generate_manifest(deployed, version, generate_manifest)} do
      result = %{
        version: version,
        destination: destination,
        binaries_deployed: length(deployed),
        deployed_files: deployed,
        manifest: manifest
      }

      {:ok, result}
    else
      {step, error} ->
        Logger.error("Deployment failed at step #{step}: #{inspect(error)}")
        {:error, {step, error}}
    end
  end

  @doc """
  Finds all distributable binaries in a directory
  """
  def find_distributable_binaries(source_path, version) do
    case get_dist_directory(source_path, version) do
      {:ok, dist_path} ->
        if File.exists?(dist_path) do
          binaries =
            Path.join(dist_path, "tailwindcss*")
            |> Path.wildcard()
            |> Enum.map(&get_binary_info/1)

          {:ok, binaries}
        else
          {:error, {:dist_directory_not_found, dist_path}}
        end

      error ->
        error
    end
  end

  @doc """
  Validates that binaries are ready for distribution
  """
  def validate_binaries(binaries) when is_list(binaries) do
    validation_results = Enum.map(binaries, &validate_single_binary/1)

    failed_validations =
      Enum.filter(validation_results, fn
        {:error, _} -> true
        _ -> false
      end)

    case failed_validations do
      [] -> :ok
      failures -> {:error, {:validation_failed, failures}}
    end
  end

  @doc """
  Uploads binaries to R2/S3
  """
  def deploy_to_r2(binaries, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, "defdo")
    prefix = Keyword.get(opts, :prefix, "tailwind_cli_daisyui")
    version = Keyword.get(opts, :version)

    if version == nil do
      {:error, :version_required}
    else
      upload_results =
        Enum.map(binaries, fn binary ->
          deploy_single_binary_to_r2(binary, bucket, prefix, version)
        end)

      # Check if there were errors
      failures =
        Enum.filter(upload_results, fn
          {:error, _} -> true
          _ -> false
        end)

      case failures do
        [] -> {:ok, upload_results}
        _ -> {:error, {:upload_failures, failures}}
      end
    end
  end

  @doc """
  Generates a deployment manifest
  """
  def generate_deployment_manifest(deployed_files, version, opts \\ []) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    compilation_info = Core.get_compilation_details(version)

    manifest = %{
      version: version,
      timestamp: timestamp,
      compilation_method: compilation_info.compilation_method,
      host_architecture: compilation_info.host_architecture,
      total_files: length(deployed_files),
      files: Enum.map(deployed_files, &format_file_info/1),
      metadata: %{
        cross_compilation_available: compilation_info.cross_compilation_available,
        supported_targets: compilation_info.supported_targets,
        limitations: compilation_info.limitations
      }
    }

    case Keyword.get(opts, :format, :map) do
      :json -> {:ok, Jason.encode!(manifest, pretty: true)}
      :map -> {:ok, manifest}
    end
  end

  @doc """
  Obtiene información detallada de un binario
  """
  def get_binary_info(file_path) when is_binary(file_path) do
    stat = File.stat!(file_path)

    %{
      path: file_path,
      filename: Path.basename(file_path),
      size: stat.size,
      size_mb: Float.round(stat.size / (1024 * 1024), 2),
      modified: stat.mtime,
      architecture: extract_architecture_from_filename(Path.basename(file_path)),
      executable: is_executable?(file_path)
    }
  end

  @doc """
  Verifica si un archivo es ejecutable
  """
  def is_executable?(file_path) do
    case File.stat(file_path) do
      {:ok, %{mode: mode}} ->
        # Verificar si tiene permisos de ejecución
        import Bitwise
        (mode &&& 0o111) != 0

      _ ->
        false
    end
  end

  # Funciones privadas

  defp maybe_validate_binaries(binaries, true), do: validate_binaries(binaries)
  defp maybe_validate_binaries(_binaries, false), do: :ok

  defp maybe_generate_manifest(deployed_files, version, true) do
    generate_deployment_manifest(deployed_files, version)
  end

  defp maybe_generate_manifest(_deployed_files, _version, false), do: {:ok, nil}

  defp filter_binaries_for_deploy(binaries, version) do
    case Core.get_version_constraints(version) do
      %{major_version: :v4} ->
        host_arch = Core.get_host_architecture()

        filtered =
          Enum.filter(binaries, fn %{architecture: arch} ->
            match_architecture?(arch, host_arch)
          end)

        case filtered do
          [] -> {:error, {:no_binaries_for_host, host_arch}}
          list -> {:ok, list}
        end

      _ ->
        {:ok, binaries}
    end
  end

  defp get_dist_directory(source_path, version) do
    case Core.get_version_constraints(version) do
      %{major_version: :v3} ->
        dist_path = Path.join([source_path, "tailwindcss-#{version}", "standalone-cli", "dist"])
        {:ok, dist_path}

      %{major_version: :v4} ->
        dist_path =
          Path.join([
            source_path,
            "tailwindcss-#{version}",
            "packages",
            "@tailwindcss-standalone",
            "dist"
          ])

        {:ok, dist_path}

      _ ->
        {:error, :unsupported_version}
    end
  end

  defp validate_single_binary(binary_info) do
    cond do
      # Menos de 10 bytes parece muy pequeño (se permiten archivos de test)
      binary_info.size < 10 ->
        {:error, {:file_too_small, binary_info.filename}}

      # Más de 500MB parece muy grande (TailwindCSS v4.x puede ser más grande)
      binary_info.size > 500_000_000 ->
        {:error, {:file_too_large, binary_info.filename}}

      true ->
        {:ok, binary_info}
    end
  end

  defp deploy_binaries(binaries, :r2, opts) do
    deploy_to_r2(binaries, opts)
  end

  defp deploy_binaries(binaries, :s3, opts) do
    # Same implementation
    deploy_to_r2(binaries, opts)
  end

  defp deploy_binaries(_binaries, destination, _opts) do
    {:error, {:unsupported_destination, destination}}
  end

  defp deploy_single_binary_to_r2(binary_info, bucket, prefix, version) do
    filename = binary_info.filename
    object_key = "#{prefix}/v#{version}/#{filename}"

    Logger.info("Uploading #{filename} to #{bucket}/#{object_key}")

    try do
      # Build S3 URL and credentials from environment
      access_key_id = Application.get_env(:tailwind_builder, :aws)[:access_key_id]
      secret_access_key = Application.get_env(:tailwind_builder, :aws)[:secret_access_key]
      host = Application.get_env(:tailwind_builder, :aws)[:host]
      region = Application.get_env(:tailwind_builder, :aws)[:region] || "auto"

      # Create Req client with S3 plugin
      req =
        Req.new(base_url: "https://#{host}")
        |> ReqS3.attach(
          aws_sigv4: [
            access_key_id: access_key_id,
            secret_access_key: secret_access_key,
            region: region,
            service: "s3"
          ]
        )

      # Read file and upload using the s3 operation
      file_content = File.read!(binary_info.path)

      result = Req.put!(req, url: "/#{bucket}/#{object_key}", body: file_content)

      if result.status in 200..299 do
        Logger.info("Successfully uploaded #{filename}")

        {:ok,
         %{
           local_path: binary_info.path,
           remote_key: object_key,
           bucket: bucket,
           size: binary_info.size,
           upload_result: %{status: result.status, headers: result.headers}
         }}
      else
        raise "Upload failed with status #{result.status}"
      end
    rescue
      error ->
        Logger.error("Failed to upload #{filename}: #{inspect(error)}")
        {:error, {:upload_failed, filename, error}}
    end
  end

  defp extract_architecture_from_filename(filename) do
    normalized = String.downcase(filename)

    cond do
      matches_any?(normalized, ["darwin", "macos", "apple"]) &&
          matches_any?(normalized, ["arm64", "aarch64"]) ->
        "darwin-arm64"

      matches_any?(normalized, ["darwin", "macos", "apple"]) &&
          matches_any?(normalized, ["x86_64", "x64"]) ->
        "darwin-x64"

      String.contains?(normalized, "linux") &&
          matches_any?(normalized, ["arm64", "aarch64"]) ->
        "linux-arm64"

      String.contains?(normalized, "linux") && matches_any?(normalized, ["armv7", "arm"]) ->
        "linux-arm"

      String.contains?(normalized, "linux") && matches_any?(normalized, ["x86_64", "x64"]) ->
        "linux-x64"

      matches_any?(normalized, ["win32", "windows"]) &&
          matches_any?(normalized, ["arm64", "aarch64"]) ->
        "win32-arm64"

      matches_any?(normalized, ["win32", "windows"]) &&
          matches_any?(normalized, ["x86_64", "x64"]) ->
        "win32-x64"

      String.contains?(normalized, "freebsd") ->
        "freebsd-x64"

      true ->
        "unknown"
    end
  end

  defp matches_any?(string, patterns) do
    Enum.any?(patterns, &String.contains?(string, &1))
  end

  defp match_architecture?("unknown", _host), do: false

  defp match_architecture?(binary_arch, host_arch) do
    normalize_arch(binary_arch) == normalize_arch(host_arch)
  end

  defp normalize_arch(arch) when is_binary(arch) do
    arch
    |> String.replace(~r/-gnu$/, "")
    |> String.replace(~r/-musl$/, "")
    |> String.replace(~r/-msvc$/, "")
  end

  defp format_file_info({:ok, deployed_info}) do
    %{
      filename: Path.basename(deployed_info.local_path),
      remote_key: deployed_info.remote_key,
      size_bytes: deployed_info.size,
      size_mb: Float.round(deployed_info.size / (1024 * 1024), 2),
      architecture: extract_architecture_from_filename(Path.basename(deployed_info.local_path))
    }
  end

  defp format_file_info({:error, {_step, filename, _error}}) do
    %{
      filename: filename,
      status: "failed",
      error: "upload_failed"
    }
  end

  # Handle raw binary info maps (for direct usage from tests/external calls)
  defp format_file_info(%{filename: filename, size: size} = binary_info)
       when is_map(binary_info) do
    %{
      filename: filename,
      # Not deployed yet
      remote_key: nil,
      size_bytes: size,
      size_mb: Float.round(size / (1024 * 1024), 2),
      architecture: extract_architecture_from_filename(filename),
      status: "pending"
    }
  end
end
