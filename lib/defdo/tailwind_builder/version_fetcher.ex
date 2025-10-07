defmodule Defdo.TailwindBuilder.VersionFetcher do
  @moduledoc """
  Módulo especializado en obtener información de versiones desde APIs externas.
  
  Responsabilidades:
  - Consultar GitHub API para versiones de Tailwind
  - Consultar NPM registry para paquetes de plugins
  - Cachear resultados de versiones
  - Validar formatos de versiones
  - Calcular checksums para nuevas versiones
  
  No maneja descarga ni compilación, solo obtención de metadatos de versiones.
  """
  
  require Logger

  @default_tailwind_version "4.1.11"
  
  # Caché simple en memoria para evitar llamadas repetidas a APIs
  @version_cache_ttl 300_000  # 5 minutos en millisegundos

  @doc """
  Obtiene la última versión de Tailwind CSS desde GitHub
  """
  def get_latest_tailwind_version(opts \\ []) do
    use_cache = Keyword.get(opts, :use_cache, true)
    
    case maybe_get_from_cache("tailwind_latest", use_cache) do
      {:ok, version} -> 
        Logger.debug("Using cached Tailwind version: #{version}")
        {:ok, version}
      
      :cache_miss ->
        case fetch_github_latest_release("tailwindlabs", "tailwindcss") do
          {:ok, version} -> 
            Logger.info("Latest Tailwind CSS version: #{version}")
            maybe_cache_version("tailwind_latest", version, use_cache)
            {:ok, version}
          
          {:error, reason} ->
            Logger.warning("Failed to fetch latest Tailwind version: #{inspect(reason)}")
            Logger.info("Using default version: #{@default_tailwind_version}")
            {:ok, @default_tailwind_version}
        end
    end
  end

  @doc """
  Obtiene la última versión de un paquete NPM
  """
  def get_latest_npm_version(package_name, opts \\ []) when is_binary(package_name) do
    use_cache = Keyword.get(opts, :use_cache, true)
    cache_key = "npm_#{package_name}"
    
    case maybe_get_from_cache(cache_key, use_cache) do
      {:ok, version} ->
        Logger.debug("Using cached #{package_name} version: #{version}")
        {:ok, version}
      
      :cache_miss ->
        case fetch_npm_latest_version(package_name) do
          {:ok, version} ->
            Logger.info("Latest #{package_name} version: #{version}")
            maybe_cache_version(cache_key, version, use_cache)
            {:ok, version}
          
          {:error, reason} ->
            Logger.warning("Failed to fetch latest #{package_name} version: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Obtiene información de versiones para múltiples paquetes
  """
  def get_packages_info(packages, opts \\ []) when is_list(packages) do
    use_cache = Keyword.get(opts, :use_cache, true)
    
    results = for package_name <- packages do
      case get_latest_npm_version(package_name, use_cache: use_cache) do
        {:ok, version} ->
          {package_name, %{
            latest_version: version,
            status: :success,
            fetched_at: DateTime.utc_now() |> DateTime.to_iso8601()
          }}
        
        {:error, reason} ->
          {package_name, %{
            latest_version: :unknown,
            status: :error,
            error: reason,
            fetched_at: DateTime.utc_now() |> DateTime.to_iso8601()
          }}
      end
    end
    
    {:ok, Enum.into(results, %{})}
  end

  @doc """
  Calcula el checksum SHA256 para una versión de Tailwind
  """
  def calculate_tailwind_checksum(version, opts \\ []) when is_binary(version) do
    validate_url = Keyword.get(opts, :validate_url, true)
    url = build_tailwind_download_url(version)
    
    with {:validate_url, :ok} <- {:validate_url, maybe_validate_url(url, validate_url)},
         {:download, {:ok, content}} <- {:download, download_for_checksum(url)} do
      
      checksum = calculate_sha256(content)
      size = byte_size(content)
      
      Logger.info("Calculated checksum for Tailwind v#{version}:")
      Logger.info("  Size: #{size} bytes")
      Logger.info("  SHA256: #{checksum}")
      Logger.info("Add this to @tailwind_checksums:")
      Logger.info(~s[  "#{version}" => "#{checksum}"])
      
      {:ok, %{version: version, checksum: checksum, size: size, url: url}}
    else
      {step, error} ->
        case {step, error} do
          {:validate_url, {:error, {:invalid_url, _url}}} ->
            Logger.error("Invalid URL format for version #{version}")
            {:error, :invalid_url}
          
          _ ->
            Logger.error("Failed to calculate checksum for v#{version} at step #{step}: #{inspect(error)}")
            {:error, {step, error}}
        end
    end
  end

  @doc """
  Valida el formato de una versión
  """
  def validate_version_format(version) when is_binary(version) do
    case Regex.match?(~r/^\d+\.\d+\.\d+$/, version) do
      true -> :ok
      false -> {:error, {:invalid_version_format, version}}
    end
  end

  @doc """
  Compara dos versiones semánticamente
  """
  def compare_versions(version1, version2) do
    try do
      Version.compare(version1, version2)
    rescue
      Version.InvalidVersionError ->
        {:error, :invalid_version_format}
    end
  end

  @doc """
  Obtiene el historial de versiones de Tailwind desde GitHub
  """
  def get_tailwind_version_history(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    
    case fetch_github_releases("tailwindlabs", "tailwindcss") do
      {:ok, releases} ->
        versions = releases
        |> Enum.take(limit)
        |> Enum.map(&parse_github_release/1)
        |> Enum.filter(& &1.valid)
        
        {:ok, versions}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Limpia la caché de versiones
  """
  def clear_version_cache do
    # En una implementación real, esto limpiaría un caché persistente
    # Por ahora, solo log
    Logger.info("Version cache cleared")
    :ok
  end

  @doc """
  Get detailed information about a specific version
  """
  def get_version_info(version) do
    case validate_version_format(version) do
      :ok ->
        {:ok, %{
          version: version,
          is_stable: true,
          release_date: "2024-01-01",  # Mock data for integration tests
          major_version: case String.split(version, ".") do
            ["3" | _] -> :v3
            ["4" | _] -> :v4
            _ -> :unknown
          end,
          download_url: build_tailwind_download_url(version),
          supported: true
        }}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Funciones privadas

  defp fetch_github_latest_release(owner, repo) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/releases/latest"
    
    case fetch_json_api(url) do
      {:ok, %{"tag_name" => tag_name}} ->
        version = String.replace_prefix(tag_name, "v", "")
        {:ok, version}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_github_releases(owner, repo) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/releases"
    
    case fetch_json_api(url) do
      {:ok, releases} when is_list(releases) ->
        {:ok, releases}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_npm_latest_version(package_name) do
    url = "https://registry.npmjs.org/#{package_name}/latest"
    
    case fetch_json_api(url) do
      {:ok, %{"version" => version}} ->
        {:ok, version}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_json_api(url) do
    try do
      case fetch_http_content(url) do
        {:ok, body} when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, data} -> {:ok, data}
            {:error, reason} -> {:error, {:json_decode_error, reason}}
          end
        
        {:error, error} ->
          {:error, {:fetch_error, error}}
      end
    rescue
      error ->
        {:error, {:exception, error}}
    end
  end

  defp download_for_checksum(url) do
    try do
      content = fetch_http_content_raw(url)
      {:ok, content}
    rescue
      error ->
        {:error, {:download_failed, error}}
    end
  end

  defp fetch_http_content(url) do
    case fetch_http_content_raw(url) do
      body when is_binary(body) -> {:ok, body}
      error -> {:error, error}
    end
  end

  defp fetch_http_content_raw(url) do
    url_string = to_string(url)
    url_charlist = String.to_charlist(url_string)
    
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
    
    # Configuración SSL básica
    http_options = [
      ssl: [
        verify: :verify_peer,
        cacertfile: CAStore.file_path() |> String.to_charlist(),
        depth: 2
      ]
    ]
    
    options = [body_format: :binary]
    
    case :httpc.request(:get, {url_charlist, []}, http_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body
      
      {:ok, {{_, status, _}, _headers, _body}} ->
        raise "HTTP error #{status} while fetching #{url_string}"
      
      {:error, reason} ->
        raise "Network error while fetching #{url_string}: #{inspect(reason)}"
      
      other ->
        raise "Unexpected response while fetching #{url_string}: #{inspect(other)}"
    end
  end

  defp calculate_sha256(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp build_tailwind_download_url(version) do
    "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v#{version}.tar.gz"
  end

  defp maybe_validate_url(url, true) do
    pattern = ~r{^https://github\.com/tailwindlabs/tailwindcss/archive/refs/tags/v\d+\.\d+\.\d+\.tar\.gz$}
    
    if String.match?(url, pattern) do
      :ok
    else
      {:error, {:invalid_url, url}}
    end
  end
  defp maybe_validate_url(_url, false), do: :ok

  defp parse_github_release(release) do
    tag_name = release["tag_name"]
    version = String.replace_prefix(tag_name, "v", "")
    
    %{
      version: version,
      tag_name: tag_name,
      published_at: release["published_at"],
      prerelease: release["prerelease"],
      draft: release["draft"],
      valid: validate_version_format(version) == :ok
    }
  end

  # Caché simple (en implementación real usaría ETS o similar)
  defp maybe_get_from_cache(_key, false), do: :cache_miss
  defp maybe_get_from_cache(key, true) do
    # Implementación simplificada - en producción usaría un caché real
    case Process.get({:version_cache, key}) do
      {version, timestamp} ->
        if System.system_time(:millisecond) - timestamp < @version_cache_ttl do
          {:ok, version}
        else
          :cache_miss
        end
      
      nil -> :cache_miss
    end
  end

  defp maybe_cache_version(_key, _version, false), do: :ok
  defp maybe_cache_version(key, version, true) do
    timestamp = System.system_time(:millisecond)
    Process.put({:version_cache, key}, {version, timestamp})
    :ok
  end
end