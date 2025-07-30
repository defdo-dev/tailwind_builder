defmodule Defdo.TailwindBuilder.Downloader do
  @moduledoc """
  Specialized module for downloading and extracting files with comprehensive telemetry.
  
  Responsibilities:
  - Download files from URLs with telemetry tracking
  - Validate integrity with checksums
  - Extract tar.gz files
  - URL validation and download security
  - Performance monitoring and error tracking
  
  Following Unix principle: "do one thing and do it well"
  """
  
  require Logger
  alias Defdo.TailwindBuilder.{Telemetry, Metrics}

  @doc """
  Download and extract a Tailwind CSS file from GitHub with telemetry tracking
  """
  def download_and_extract(opts \\ []) do
    # Use telemetry wrapper for comprehensive tracking
    Telemetry.track_download(opts[:version] || "unknown", fn ->
      do_download_and_extract(opts)
    end)
  end

  defp do_download_and_extract(opts) do
    opts = Keyword.validate!(opts, [
      :version,
      :destination,
      :url,
      :expected_checksum,
      :validate_url
    ])
    
    version = opts[:version] || raise ArgumentError, "version is required"
    destination = opts[:destination] || File.cwd!()
    
    # Build URL if not provided
    url = opts[:url] || build_github_url(version)
    
    # Track download start
    start_time = System.monotonic_time()
    Telemetry.track_event(:download, :start, %{version: version, url: url, destination: destination})
    
    # Validate URL if required (default true)
    validate_url = Keyword.get(opts, :validate_url, true)
    
    with {:validate_url, :ok} <- {:validate_url, maybe_validate_url_with_telemetry(url, validate_url)},
         {:download, {:ok, content}} <- {:download, download_content_with_telemetry(url, version)},
         {:validate_checksum, :ok} <- {:validate_checksum, maybe_validate_checksum_with_telemetry(content, version, opts[:expected_checksum])},
         {:save, {:ok, tar_path}} <- {:save, save_content_with_telemetry(content, destination, version)},
         {:extract, :ok} <- {:extract, extract_tar_with_telemetry(tar_path)},
         {:cleanup, :ok} <- {:cleanup, cleanup_tar(tar_path)} do
      
      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
      
      result = %{
        version: version,
        destination: destination,
        extracted_path: Path.join(destination, "tailwindcss-#{version}"),
        url: url,
        size: byte_size(content),
        duration_ms: duration_ms
      }
      
      # Record comprehensive metrics
      Metrics.record_download_metrics(version, byte_size(content), duration_ms, :success)
      Telemetry.track_event(:download, :success, %{version: version, size: byte_size(content), duration_ms: duration_ms})
      
      {:ok, result}
    else
      {step, error} ->
        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
        
        # Record error metrics
        Metrics.record_error_metrics(:download, step, error)
        Metrics.record_download_metrics(version, 0, duration_ms, :error)
        Telemetry.track_event(:download, :error, %{version: version, step: step, error: inspect(error), duration_ms: duration_ms})
        
        Logger.error("Download failed at step #{step}: #{inspect(error)}")
        {:error, {step, error}}
    end
  end

  @doc """
  Descarga contenido desde una URL con validaciones de seguridad
  """
  def download_content(url) when is_binary(url) do
    Logger.debug("Downloading from #{url}")
    
    try do
      content = fetch_with_security(url)
      {:ok, content}
    rescue
      error ->
        {:error, {:download_failed, error}}
    end
  end

  @doc """
  Valida la integridad de un archivo descargado usando checksum
  """
  def validate_checksum(content, expected_checksum) when is_binary(content) and is_binary(expected_checksum) do
    actual_checksum = calculate_sha256(content)
    
    if actual_checksum == expected_checksum do
      Logger.debug("Checksum validation passed: #{actual_checksum}")
      :ok
    else
      Logger.error("Checksum mismatch!")
      Logger.error("Expected: #{expected_checksum}")
      Logger.error("Actual:   #{actual_checksum}")
      {:error, :checksum_mismatch}
    end
  end

  @doc """
  Extrae un archivo tar.gz en su directorio padre
  """
  def extract_tar(tar_path) when is_binary(tar_path) do
    if File.exists?(tar_path) do
      Logger.debug("Extracting #{tar_path}")
      
      case :erl_tar.extract(tar_path, [:compressed, {:cwd, Path.dirname(tar_path)}]) do
        :ok ->
          Logger.info("Extraction successful")
          :ok
        error ->
          Logger.error("Extraction failed: #{inspect(error)}")
          {:error, {:extraction_failed, error}}
      end
    else
      {:error, {:file_not_found, tar_path}}
    end
  end

  @doc """
  Calcula el checksum SHA256 de contenido binario
  """
  def calculate_sha256(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Valida que una URL sea de GitHub y del repositorio oficial de Tailwind
  """
  def validate_github_url(url) when is_binary(url) do
    pattern = ~r{^https://github\.com/tailwindlabs/tailwindcss/archive/refs/tags/v\d+\.\d+\.\d+\.tar\.gz$}
    
    if String.match?(url, pattern) do
      :ok
    else
      {:error, {:invalid_url, "URL must be from official Tailwind CSS repository"}}
    end
  end

  @doc """
  Construye la URL de descarga para una versión específica de Tailwind
  """
  def build_github_url(version) when is_binary(version) do
    "https://github.com/tailwindlabs/tailwindcss/archive/refs/tags/v#{version}.tar.gz"
  end

  @doc """
  Obtiene información sobre el tamaño y tipo de un archivo descargado
  """
  def get_download_info(content) when is_binary(content) do
    size = byte_size(content)
    
    %{
      size_bytes: size,
      size_kb: Float.round(size / 1024, 2),
      size_mb: Float.round(size / (1024 * 1024), 2),
      checksum: calculate_sha256(content),
      is_reasonable_size: size >= 100_000 and size <= 200_000_000  # 100KB - 200MB
    }
  end

  # Funciones privadas

  defp maybe_validate_url(url, true), do: validate_github_url(url)
  defp maybe_validate_url(_url, false), do: :ok

  # Telemetry-enhanced versions of internal functions
  
  defp maybe_validate_url_with_telemetry(url, validate_flag) do
    Telemetry.track_event(:download, :url_validation_start, %{url: url, validate: validate_flag})
    
    result = maybe_validate_url(url, validate_flag)
    
    case result do
      :ok -> 
        Telemetry.track_event(:download, :url_validation_success, %{url: url})
      error -> 
        Telemetry.track_event(:download, :url_validation_error, %{url: url, error: inspect(error)})
    end
    
    result
  end

  defp download_content_with_telemetry(url, version) do
    start_time = System.monotonic_time()
    Telemetry.track_event(:download, :http_request_start, %{url: url, version: version})
    
    result = download_content(url)
    
    end_time = System.monotonic_time()
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    case result do
      {:ok, content} ->
        size_bytes = byte_size(content)
        Telemetry.track_event(:download, :http_request_success, %{
          url: url, 
          version: version, 
          size_bytes: size_bytes, 
          duration_ms: duration_ms
        })
        Metrics.record_cache_metrics(:download, url, :miss)  # Assume cache miss for HTTP requests
      
      error ->
        Telemetry.track_event(:download, :http_request_error, %{
          url: url, 
          version: version, 
          error: inspect(error), 
          duration_ms: duration_ms
        })
    end
    
    result
  end

  defp maybe_validate_checksum_with_telemetry(content, version, expected_checksum) do
    start_time = System.monotonic_time()
    Telemetry.track_event(:download, :checksum_validation_start, %{version: version, has_expected: expected_checksum != nil})
    
    result = maybe_validate_checksum(content, version, expected_checksum)
    
    end_time = System.monotonic_time()
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    case result do
      :ok -> 
        Telemetry.track_event(:download, :checksum_validation_success, %{version: version, duration_ms: duration_ms})
      error -> 
        Telemetry.track_event(:download, :checksum_validation_error, %{version: version, error: inspect(error), duration_ms: duration_ms})
    end
    
    result
  end

  defp save_content_with_telemetry(content, destination, version) do
    start_time = System.monotonic_time()
    size_bytes = byte_size(content)
    Telemetry.track_event(:download, :file_save_start, %{destination: destination, version: version, size_bytes: size_bytes})
    
    result = save_content(content, destination, version)
    
    end_time = System.monotonic_time()
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    case result do
      {:ok, tar_path} ->
        Telemetry.track_event(:download, :file_save_success, %{
          tar_path: tar_path, 
          version: version, 
          size_bytes: size_bytes, 
          duration_ms: duration_ms
        })
      
      error ->
        Telemetry.track_event(:download, :file_save_error, %{
          destination: destination, 
          version: version, 
          error: inspect(error), 
          duration_ms: duration_ms
        })
    end
    
    result
  end

  defp extract_tar_with_telemetry(tar_path) do
    start_time = System.monotonic_time()
    file_size = case File.stat(tar_path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
    
    Telemetry.track_event(:download, :extraction_start, %{tar_path: tar_path, file_size: file_size})
    
    result = extract_tar(tar_path)
    
    end_time = System.monotonic_time()
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    case result do
      :ok ->
        Telemetry.track_event(:download, :extraction_success, %{
          tar_path: tar_path, 
          file_size: file_size, 
          duration_ms: duration_ms
        })
      
      error ->
        Telemetry.track_event(:download, :extraction_error, %{
          tar_path: tar_path, 
          error: inspect(error), 
          duration_ms: duration_ms
        })
    end
    
    result
  end

  defp maybe_validate_checksum(content, version, nil) do
    # Sin checksum esperado, solo log warning
    Logger.warning("No expected checksum provided for version #{version}")
    Logger.info("Downloaded content checksum: #{calculate_sha256(content)}")
    :ok
  end
  
  defp maybe_validate_checksum(content, _version, expected_checksum) do
    validate_checksum(content, expected_checksum)
  end

  defp save_content(content, destination, version) do
    File.mkdir_p!(destination)
    tar_path = Path.join(destination, "#{version}.tar.gz")
    
    try do
      File.write!(tar_path, content, [:binary])
      File.chmod(tar_path, 0o755)
      {:ok, tar_path}
    rescue
      error ->
        {:error, {:save_failed, error}}
    end
  end

  defp cleanup_tar(tar_path) do
    try do
      File.rm!(tar_path)
      :ok
    rescue
      error ->
        Logger.warning("Failed to cleanup tar file #{tar_path}: #{inspect(error)}")
        :ok  # No fallar por esto
    end
  end

  # Funciones de descarga con seguridad (reutilizando lógica existente)
  
  defp fetch_with_security(url) do
    url_string = to_string(url)
    url_charlist = String.to_charlist(url_string)

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    # Configurar proxies si existen
    configure_proxy()

    # Configuración SSL segura
    cacertfile = CAStore.file_path() |> String.to_charlist()

    http_options = [
      ssl: [
        verify: :verify_peer,
        cacertfile: cacertfile,
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ],
        versions: protocol_versions()
      ]
    ]

    options = [body_format: :binary]

    case :httpc.request(:get, {url_charlist, []}, http_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body
      {:ok, {{_, status, _}, _headers, _body}} ->
        raise "HTTP error #{status} while downloading #{url_string}"
      {:error, reason} ->
        raise "Network error while downloading #{url_string}: #{inspect(reason)}"
      other ->
        raise "Unexpected response while downloading #{url_string}: #{inspect(other)}"
    end
  end

  defp configure_proxy do
    if proxy = System.get_env("HTTP_PROXY") || System.get_env("http_proxy") do
      Logger.debug("Using HTTP_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:proxy, {{String.to_charlist(host), port}, []}}])
    end

    if proxy = System.get_env("HTTPS_PROXY") || System.get_env("https_proxy") do
      Logger.debug("Using HTTPS_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:https_proxy, {{String.to_charlist(host), port}, []}}])
    end
  end

  defp protocol_versions do
    if otp_version() < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
  end

  defp otp_version do
    :erlang.system_info(:otp_release) |> List.to_integer()
  end
end