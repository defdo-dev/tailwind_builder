defmodule Defdo.TailwindBuilder.ConfigProvider do
  @moduledoc """
  Behaviour para inyección de configuración externa.
  
  Permite a las capas superiores inyectar configuraciones de negocio
  sin que el Core tenga que conocer políticas específicas.
  
  ## Ejemplos de implementación
  
  ### Configuración desde archivo
      defmodule MyApp.FileConfigProvider do
        @behaviour Defdo.TailwindBuilder.ConfigProvider
        
        def get_supported_plugins do
          Application.get_env(:my_app, :tailwind_plugins, %{})
        end
        
        def get_version_policy(version) do
          case Application.get_env(:my_app, :version_policy) do
            :latest_only -> if version == get_latest_version(), do: :allowed, else: :blocked
            :all -> :allowed
          end
        end
      end
  
  ### Configuración desde base de datos
      defmodule MyApp.DatabaseConfigProvider do
        @behaviour Defdo.TailwindBuilder.ConfigProvider
        
        def get_supported_plugins do
          MyApp.Repo.all(MyApp.SupportedPlugin)
          |> Enum.into(%{}, fn plugin -> {plugin.name, plugin.config} end)
        end
      end
  """

  @doc """
  Obtiene la lista de plugins soportados con su configuración
  """
  @callback get_supported_plugins() :: %{String.t() => map()}

  @doc """
  Obtiene los checksums conocidos para versiones de Tailwind
  """
  @callback get_known_checksums() :: %{String.t() => String.t()}

  @doc """
  Determina la política para una versión específica
  Retorna :allowed, :blocked, o :deprecated
  """
  @callback get_version_policy(version :: String.t()) :: :allowed | :blocked | :deprecated

  @doc """
  Obtiene configuración específica de deployment
  """
  @callback get_deployment_config(target :: atom()) :: %{
    bucket: String.t(),
    prefix: String.t(),
    region: String.t()
  }

  @doc """
  Obtiene límites de operación (rate limiting, timeouts, etc.)
  """
  @callback get_operation_limits() :: %{
    max_concurrent_downloads: pos_integer(),
    download_timeout: pos_integer(),
    build_timeout: pos_integer(),
    max_file_size: pos_integer()
  }

  @doc """
  Obtiene políticas de construcción/compilación
  """
  @callback get_build_policies() :: %{
    allow_experimental_features: boolean(),
    skip_non_critical_validations: boolean(),
    enable_debug_symbols: boolean(),
    verbose_logging: boolean()
  }

  @doc """
  Obtiene políticas de deployment
  """
  @callback get_deployment_policies() :: %{
    skip_production_checks: boolean(),
    allow_overwrite: boolean(),
    backup_existing: boolean(),
    notify_on_deploy: boolean()
  }

  @doc """
  Valida si una operación está permitida por políticas de negocio
  """
  @callback validate_operation_policy(operation :: atom(), params :: map()) :: 
    :ok | {:warning, String.t()} | {:error, term()}

  @optional_callbacks [
    get_known_checksums: 0,
    get_version_policy: 1,
    get_deployment_config: 1,
    get_operation_limits: 0,
    get_build_policies: 0,
    get_deployment_policies: 0,
    validate_operation_policy: 2
  ]
end