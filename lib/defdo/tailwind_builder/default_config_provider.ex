defmodule Defdo.TailwindBuilder.DefaultConfigProvider do
  @moduledoc """
  Implementación por defecto del ConfigProvider.

  Proporciona configuración básica que puede ser sobrescrita
  por implementaciones específicas del usuario.
  """

  @behaviour Defdo.TailwindBuilder.ConfigProvider

  # Configuración de plugins soportados por defecto
  @default_supported_plugins %{
    "daisyui" => %{
      "version" => ~s["daisyui": "^4.12.23"],
      "statement" => ~s['daisyui': require('daisyui')],
      "description" => "Semantic component classes for Tailwind CSS",
      "npm_name" => "daisyui",
      "compatible_versions" => ["3.x"]
    },
    "daisyui_v5" => %{
      "version" => ~s["daisyui": "^5.0.49"],
      "description" => "Semantic component classes for Tailwind CSS v5",
      "npm_name" => "daisyui",
      "compatible_versions" => ["4.x"]
    }
  }

  # Checksums conocidos por defecto
  @default_checksums %{
    "3.4.17" => "89c0a7027449cbe564f8722e84108f7bfa0224b5d9289c47cc967ffef8e1b016",
    "4.0.9" => "7c36fdcdfed4d1b690a56a1267457a8ac9c640ccae2efcaed59f5053d330000a",
    "4.0.17" => "3590bcb90a75c32ba8b10d692d26838caedbc267a57db23931694abc9598c873",
    "4.1.11" => "149b7db8417a4a0419ada1d2dc428a11202fc6b971f037b7a8527371c59e0cae"
  }

  @impl true
  def get_supported_plugins do
    # Permitir sobrescribir desde configuración de aplicación
    Application.get_env(:tailwind_builder, :supported_plugins, @default_supported_plugins)
  end

  @impl true
  def get_known_checksums do
    # Permitir sobrescribir desde configuración de aplicación
    Application.get_env(:tailwind_builder, :known_checksums, @default_checksums)
  end

  @impl true
  def get_version_policy(version) do
    # Política por defecto: permitir todas las versiones con checksums conocidos
    checksums = get_known_checksums()

    cond do
      Map.has_key?(checksums, version) -> :allowed
      version_is_too_old?(version) -> :deprecated
      # Permitir versiones nuevas para experimentación
      true -> :allowed
    end
  end

  @impl true
  def get_deployment_config(:r2) do
    %{
      bucket: Application.get_env(:tailwind_builder, :r2_bucket, "defdo"),
      prefix: Application.get_env(:tailwind_builder, :r2_prefix, "tailwind_cli_daisyui"),
      region: Application.get_env(:tailwind_builder, :r2_region, "auto")
    }
  end

  def get_deployment_config(:s3) do
    %{
      bucket: Application.get_env(:tailwind_builder, :s3_bucket, "my-tailwind-builds"),
      prefix: Application.get_env(:tailwind_builder, :s3_prefix, "builds"),
      region: Application.get_env(:tailwind_builder, :s3_region, "us-east-1")
    }
  end

  def get_deployment_config(_target) do
    %{bucket: "", prefix: "", region: ""}
  end

  @impl true
  def get_operation_limits do
    %{
      max_concurrent_downloads:
        Application.get_env(:tailwind_builder, :max_concurrent_downloads, 3),
      # 5 minutos
      download_timeout: Application.get_env(:tailwind_builder, :download_timeout, 300_000),
      # 15 minutos
      build_timeout: Application.get_env(:tailwind_builder, :build_timeout, 900_000),
      # 200MB
      max_file_size: Application.get_env(:tailwind_builder, :max_file_size, 200_000_000)
    }
  end

  @impl true
  def validate_operation_policy(:download, %{version: version}) do
    case get_version_policy(version) do
      :allowed ->
        :ok

      :deprecated ->
        {:warning, "Version #{version} is deprecated but allowed"}
    end
  end

  def validate_operation_policy(:cross_compile, %{version: version}) do
    # Política de negocio: solo permitir cross-compilation en v3
    if String.starts_with?(version, "3.") do
      :ok
    else
      {:error, {:cross_compile_not_supported, "Cross-compilation only supported in Tailwind v3"}}
    end
  end

  def validate_operation_policy(:plugin_install, %{plugin: plugin_name}) do
    supported_plugins = get_supported_plugins()

    if Map.has_key?(supported_plugins, plugin_name) do
      :ok
    else
      {:error, {:plugin_not_supported, "Plugin #{plugin_name} is not in supported list"}}
    end
  end

  def validate_operation_policy(_operation, _params) do
    # Por defecto, permitir operaciones no especificadas
    :ok
  end

  @doc """
  Get build policies for different versions
  """
  @impl true
  def get_build_policies do
    %{
      "3.4.17" => :allowed,
      "4.0.9" => :allowed,
      "4.0.17" => :allowed,
      "4.1.11" => :allowed
    }
  end

  @doc """
  Get deployment policies for different versions
  """
  @impl true
  def get_deployment_policies do
    %{
      "3.4.17" => :allowed,
      "4.0.9" => :allowed,
      "4.0.17" => :allowed,
      "4.1.11" => :allowed
    }
  end

  # Funciones auxiliares privadas

  defp version_is_too_old?(version) do
    try do
      # Considerar versiones anteriores a 3.0.0 como obsoletas
      Version.compare(version, "3.0.0") == :lt
    rescue
      Version.InvalidVersionError -> false
    end
  end
end
