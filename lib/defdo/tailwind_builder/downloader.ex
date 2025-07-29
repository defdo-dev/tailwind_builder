defmodule Defdo.TailwindBuilder.Downloader do
  @moduledoc """
  Módulo especializado en descarga y extracción de archivos.
  
  Responsabilidades:
  - Descargar archivos desde URLs
  - Validar integridad con checksums
  - Extraer archivos tar.gz
  - Validación de URLs y seguridad de descarga
  
  Siguiendo el principio Unix: "hacer una cosa y hacerla bien"
  """
  
  require Logger

  @doc """
  Descarga y extrae un archivo de Tailwind CSS desde GitHub
  """
  def download_and_extract(opts \\ []) do
    opts = Keyword.validate!(opts, [
      :version,
      :destination,
      :url,
      :expected_checksum,
      :validate_url
    ])
    
    version = opts[:version] || raise ArgumentError, "version is required"
    destination = opts[:destination] || File.cwd!()
    
    # Construir URL si no se proporciona
    url = opts[:url] || build_github_url(version)
    
    # Validar URL si se requiere (por defecto true)
    validate_url = Keyword.get(opts, :validate_url, true)
    
    with {:validate_url, :ok} <- {:validate_url, maybe_validate_url(url, validate_url)},
         {:download, {:ok, content}} <- {:download, download_content(url)},
         {:validate_checksum, :ok} <- {:validate_checksum, maybe_validate_checksum(content, version, opts[:expected_checksum])},
         {:save, {:ok, tar_path}} <- {:save, save_content(content, destination, version)},
         {:extract, :ok} <- {:extract, extract_tar(tar_path)},
         {:cleanup, :ok} <- {:cleanup, cleanup_tar(tar_path)} do
      
      result = %{
        version: version,
        destination: destination,
        extracted_path: Path.join(destination, "tailwindcss-#{version}"),
        url: url,
        size: byte_size(content)
      }
      
      {:ok, result}
    else
      {step, error} ->
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