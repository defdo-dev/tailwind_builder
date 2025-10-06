defmodule Defdo.TailwindBuilder.ConfigProviderFactory do
  @moduledoc """
  Factory for selecting and creating the appropriate ConfigProvider
  based on environment, configuration, or explicit selection.
  
  This module provides a centralized way to determine which ConfigProvider
  implementation to use in different contexts, with automatic detection
  and manual override capabilities.
  """

  alias Defdo.TailwindBuilder.ConfigProviders.{
    DevelopmentConfigProvider,
    ProductionConfigProvider,
    StagingConfigProvider,
    TestingConfigProvider
  }
  
  alias Defdo.TailwindBuilder.DefaultConfigProvider

  @doc """
  Get the appropriate ConfigProvider module for the current environment.
  
  Selection priority:
  1. Explicitly configured provider in application config
  2. Environment-based auto-detection
  3. Default provider as fallback
  
  ## Examples
  
      # Auto-detect based on Mix environment
      provider = ConfigProviderFactory.get_provider()
      
      # Explicitly specify environment
      provider = ConfigProviderFactory.get_provider(:production)
      
      # Use custom provider
      provider = ConfigProviderFactory.get_provider(MyApp.CustomConfigProvider)
  """
  def get_provider(override \\ nil)

  def get_provider(nil) do
    # Check for explicit configuration first
    case Application.get_env(:tailwind_builder, :config_provider) do
      nil -> auto_detect_provider()
      provider when is_atom(provider) -> provider
      provider -> raise ArgumentError, "Invalid config provider: #{inspect(provider)}"
    end
  end

  def get_provider(environment) when environment in [:development, :dev] do
    DevelopmentConfigProvider
  end

  def get_provider(:production) do
    ProductionConfigProvider
  end

  def get_provider(environment) when environment in [:staging, :stage] do
    StagingConfigProvider
  end

  def get_provider(environment) when environment in [:test, :testing] do
    TestingConfigProvider
  end

  def get_provider(:default) do
    DefaultConfigProvider
  end

  def get_provider(provider) when is_atom(provider) do
    # Check if it's a known environment first
    case provider do
      env when env in [:development, :dev, :production, :staging, :stage, :test, :testing, :default] ->
        get_provider(env)
      _ ->
        # Validate that the provider implements the behavior
        if implements_config_provider?(provider) do
          provider
        else
          raise ArgumentError, "Module #{provider} does not implement ConfigProvider behavior"
        end
    end
  end

  def get_provider(invalid) do
    raise ArgumentError, "Invalid environment or provider: #{inspect(invalid)}"
  end

  @doc """
  Auto-detect the appropriate ConfigProvider based on current environment
  and configuration.
  """
  def auto_detect_provider do
    cond do
      # Check explicit environment variables first
      System.get_env("TAILWIND_BUILDER_ENV") == "production" ->
        ProductionConfigProvider
      
      System.get_env("TAILWIND_BUILDER_ENV") == "staging" ->
        StagingConfigProvider
      
      System.get_env("TAILWIND_BUILDER_ENV") == "development" ->
        DevelopmentConfigProvider
      
      System.get_env("TAILWIND_BUILDER_ENV") == "testing" ->
        TestingConfigProvider
      
      # Check CI environment
      is_ci_environment?() ->
        TestingConfigProvider
      
      # Use Mix environment
      Mix.env() == :prod ->
        ProductionConfigProvider
      
      Mix.env() == :staging ->
        StagingConfigProvider
      
      Mix.env() == :test ->
        TestingConfigProvider
      
      Mix.env() == :dev ->
        DevelopmentConfigProvider
      
      # Default fallback
      true ->
        DefaultConfigProvider
    end
  end

  @doc """
  Create a configured instance of the selected provider.
  
  This allows for runtime configuration and dependency injection
  of the ConfigProvider.
  """
  def create_provider(provider_module, opts \\ []) do
    case Keyword.get(opts, :instance_type, :module) do
      :module ->
        # Return the module itself (stateless)
        provider_module
      
      :process ->
        # Start a GenServer instance (if the provider supports it)
        if function_exported?(provider_module, :start_link, 1) do
          {:ok, pid} = provider_module.start_link(opts)
          pid
        else
          raise ArgumentError, "Provider #{provider_module} does not support process instances"
        end
      
      :agent ->
        # Create an Agent with provider state (if supported)
        if function_exported?(provider_module, :get_initial_state, 1) do
          initial_state = provider_module.get_initial_state(opts)
          {:ok, agent} = Agent.start_link(fn -> {provider_module, initial_state} end)
          agent
        else
          raise ArgumentError, "Provider #{provider_module} does not support agent instances"
        end
    end
  end

  @doc """
  Get provider information for debugging and introspection.
  """
  def get_provider_info(provider \\ nil) do
    provider_module = provider || get_provider()
    
    %{
      module: provider_module,
      environment: detect_environment_for_provider(provider_module),
      features: get_provider_features(provider_module),
      config_keys: get_provider_config_keys(provider_module),
      supports_runtime_config: supports_runtime_config?(provider_module),
      version: get_provider_version(provider_module)
    }
  end

  @doc """
  List all available ConfigProvider implementations.
  """
  def list_available_providers do
    [
      %{
        module: DefaultConfigProvider,
        name: "Default",
        description: "Basic default configuration",
        environments: [:any]
      },
      %{
        module: DevelopmentConfigProvider,
        name: "Development", 
        description: "Optimized for development workflows",
        environments: [:development, :dev]
      },
      %{
        module: ProductionConfigProvider,
        name: "Production",
        description: "Production-ready with strict policies",
        environments: [:production, :prod]
      },
      %{
        module: StagingConfigProvider,
        name: "Staging",
        description: "Pre-production testing environment",
        environments: [:staging, :stage]
      },
      %{
        module: TestingConfigProvider,
        name: "Testing",
        description: "Optimized for automated testing",
        environments: [:test, :testing, :ci]
      }
    ]
  end

  @doc """
  Validate that a provider configuration is valid and complete.
  """
  def validate_provider_config(provider \\ nil) do
    provider_module = provider || get_provider()
    
    with :ok <- validate_behavior_implementation(provider_module),
         :ok <- validate_required_functions(provider_module),
         :ok <- validate_configuration_consistency(provider_module) do
      {:ok, "Provider configuration is valid"}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Switch to a different provider at runtime (for testing/development).
  """
  def switch_provider(new_provider) do
    if implements_config_provider?(new_provider) do
      Application.put_env(:tailwind_builder, :config_provider, new_provider)
      {:ok, "Switched to #{new_provider}"}
    else
      {:error, "Invalid provider: #{new_provider}"}
    end
  end

  # Private helper functions

  defp implements_config_provider?(module) do
    try do
      # Check if module exists and implements the behavior
      Code.ensure_loaded?(module) and
      function_exported?(module, :get_supported_plugins, 0) and
      function_exported?(module, :get_known_checksums, 0) and
      function_exported?(module, :get_version_policy, 1) and
      function_exported?(module, :get_operation_limits, 0) and
      function_exported?(module, :get_deployment_config, 1) and
      function_exported?(module, :get_build_policies, 0) and
      function_exported?(module, :get_deployment_policies, 0) and
      function_exported?(module, :validate_operation_policy, 2)
    rescue
      _ -> false
    end
  end

  defp is_ci_environment? do
    ci_indicators = [
      "CI", "CONTINUOUS_INTEGRATION", "GITHUB_ACTIONS", 
      "GITLAB_CI", "CIRCLECI", "TRAVIS", "JENKINS_URL"
    ]
    
    Enum.any?(ci_indicators, &System.get_env/1)
  end

  defp detect_environment_for_provider(provider_module) do
    case provider_module do
      DevelopmentConfigProvider -> :development
      ProductionConfigProvider -> :production
      StagingConfigProvider -> :staging
      TestingConfigProvider -> :testing
      DefaultConfigProvider -> :default
      _ -> :custom
    end
  end

  defp get_provider_features(provider_module) do
    features = []
    
    features = if function_exported?(provider_module, :get_logging_config, 0),
      do: [:logging | features], else: features
    
    features = if function_exported?(provider_module, :get_cache_config, 0),
      do: [:caching | features], else: features
    
    features = if function_exported?(provider_module, :get_monitoring_config, 0),
      do: [:monitoring | features], else: features
    
    features = if function_exported?(provider_module, :get_security_config, 0),
      do: [:security | features], else: features
    
    features
  end

  defp get_provider_config_keys(provider_module) do
    try do
      # Try to get all configuration by calling the functions
      base_keys = [:supported_plugins, :known_checksums, :version_policy, 
                   :operation_limits, :deployment_config, :build_policies, 
                   :deployment_policies]
      
      optional_keys = get_provider_features(provider_module)
      
      base_keys ++ optional_keys
    rescue
      _ -> [:unknown]
    end
  end

  defp supports_runtime_config?(provider_module) do
    function_exported?(provider_module, :update_config, 2) or
    function_exported?(provider_module, :reload_config, 0)
  end

  defp get_provider_version(provider_module) do
    if function_exported?(provider_module, :__version__, 0) do
      provider_module.__version__()
    else
      "unknown"
    end
  end

  defp validate_behavior_implementation(provider_module) do
    if implements_config_provider?(provider_module) do
      :ok
    else
      {:error, "Provider does not implement ConfigProvider behavior"}
    end
  end

  defp validate_required_functions(provider_module) do
    required_functions = [
      {:get_supported_plugins, 0},
      {:get_known_checksums, 0},
      {:get_version_policy, 1},
      {:get_operation_limits, 0},
      {:get_deployment_config, 1},
      {:get_build_policies, 0},
      {:get_deployment_policies, 0},
      {:validate_operation_policy, 2}
    ]
    
    missing = Enum.reject(required_functions, fn {fun, arity} ->
      function_exported?(provider_module, fun, arity)
    end)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required functions: #{inspect(missing)}"}
    end
  end

  defp validate_configuration_consistency(provider_module) do
    try do
      # Test that basic functions can be called without errors
      _plugins = provider_module.get_supported_plugins()
      _checksums = provider_module.get_known_checksums()
      _limits = provider_module.get_operation_limits()
      _build_policies = provider_module.get_build_policies()
      _deploy_policies = provider_module.get_deployment_policies()
      
      :ok
    rescue
      error ->
        {:error, "Configuration validation failed: #{inspect(error)}"}
    end
  end
end