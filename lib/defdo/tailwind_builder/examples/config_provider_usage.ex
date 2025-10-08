defmodule Defdo.TailwindBuilder.Examples.ConfigProviderUsage do
  @moduledoc """
  Examples demonstrating how to use different ConfigProviders
  for various environments and scenarios.

  This module shows practical usage patterns for:
  - Environment-specific configuration
  - Runtime provider switching
  - Custom configuration scenarios
  - Integration with the Orchestrator
  """

  alias Defdo.TailwindBuilder.ConfigProviderFactory

  alias Defdo.TailwindBuilder.ConfigProviders.{
    DevelopmentConfigProvider,
    ProductionConfigProvider,
    StagingConfigProvider,
    TestingConfigProvider
  }

  @doc """
  Example 1: Basic environment-based provider selection
  """
  def example_environment_selection do
    IO.puts("=== Environment-Based Provider Selection ===")

    # Get provider based on current environment
    current_provider = ConfigProviderFactory.get_provider()
    IO.puts("Current provider: #{inspect(current_provider)}")

    # Get provider info
    info = ConfigProviderFactory.get_provider_info(current_provider)
    IO.puts("Environment: #{info.environment}")
    IO.puts("Features: #{inspect(info.features)}")

    # Show operation limits for current environment
    limits = current_provider.get_operation_limits()
    IO.puts("Download timeout: #{limits.download_timeout}ms")
    IO.puts("Build timeout: #{limits.build_timeout}ms")
    IO.puts("Max concurrent downloads: #{limits.max_concurrent_downloads}")
  end

  @doc """
  Example 2: Development workflow with DevelopmentConfigProvider
  """
  def example_development_workflow do
    IO.puts("=== Development Workflow ===")

    provider = DevelopmentConfigProvider

    # Show development-friendly settings
    limits = provider.get_operation_limits()
    IO.puts("Fast development timeouts:")
    IO.puts("  - Download: #{limits.download_timeout}ms")
    IO.puts("  - Build: #{limits.build_timeout}ms")

    # Show extensive plugin support
    plugins = provider.get_supported_plugins()
    IO.puts("Available plugins in development: #{map_size(plugins)}")

    for {plugin_name, _config} <- plugins do
      IO.puts("  - #{plugin_name}")
    end

    # Show permissive version policy
    versions_to_test = ["3.4.17", "4.1.11", "4.2.0-beta.1", "experimental-version"]

    IO.puts("\nVersion policies:")

    for version <- versions_to_test do
      policy = provider.get_version_policy(version)
      IO.puts("  - #{version}: #{policy}")
    end

    # Show development-specific features
    logging = provider.get_logging_config()
    IO.puts("\nDevelopment logging:")
    IO.puts("  - Level: #{logging.level}")
    IO.puts("  - Pretty print: #{logging.pretty_print}")
    IO.puts("  - HTTP requests: #{logging.log_http_requests}")
  end

  @doc """
  Example 3: Production deployment with ProductionConfigProvider
  """
  def example_production_deployment do
    IO.puts("=== Production Deployment ===")

    provider = ProductionConfigProvider

    # Show strict version policy
    versions_to_test = ["3.4.17", "4.1.11", "4.0.9", "4.2.0-beta.1"]

    IO.puts("Production version policies:")

    for version <- versions_to_test do
      policy = provider.get_version_policy(version)

      status =
        case policy do
          :allowed -> "✓ ALLOWED"
          :deprecated -> "⚠ DEPRECATED"
          :blocked -> "✗ BLOCKED"
        end

      IO.puts("  - #{version}: #{status}")
    end

    # Show security configuration
    security = provider.get_security_config()
    IO.puts("\nProduction security settings:")
    IO.puts("  - Validate checksums: #{security.validate_all_checksums}")
    IO.puts("  - Enforce HTTPS: #{security.enforce_https}")
    IO.puts("  - Rate limiting: #{security.rate_limiting.enabled}")

    # Show deployment window
    in_window = provider.in_deployment_window?()
    IO.puts("\nDeployment status:")
    IO.puts("  - Currently in deployment window: #{in_window}")

    if not in_window do
      IO.puts("  - Deployments are restricted to Monday-Thursday, 9 AM - 5 PM UTC")
    end
  end

  @doc """
  Example 4: Testing setup with TestingConfigProvider
  """
  def example_testing_setup do
    IO.puts("=== Testing Configuration ===")

    provider = TestingConfigProvider

    # Show fast testing limits
    limits = provider.get_operation_limits()
    IO.puts("Fast testing timeouts:")
    IO.puts("  - Download: #{limits.download_timeout}ms")
    IO.puts("  - Build: #{limits.build_timeout}ms")
    IO.puts("  - Retry attempts: #{limits.retry_attempts}")

    # Show mock configuration
    mocks = provider.get_mock_config()
    IO.puts("\nMocking enabled:")
    IO.puts("  - HTTP client: #{mocks.mock_http_client}")
    IO.puts("  - External tools: #{mocks.mock_external_tools}")
    IO.puts("  - Response delay: #{mocks.response_delay_ms}ms")

    # Show fixture configuration
    fixtures = provider.get_fixture_config()
    IO.puts("\nTest fixtures:")
    IO.puts("  - Directory: #{fixtures.fixtures_directory}")
    IO.puts("  - Mock downloads: #{fixtures.mock_downloads}")
    IO.puts("  - Deterministic responses: #{fixtures.deterministic_responses}")

    # Create and cleanup test directory
    test_dir = provider.create_test_directory("example")
    IO.puts("\nTest directory created: #{test_dir}")
    IO.puts("Directory exists: #{File.exists?(test_dir)}")

    provider.cleanup_test_artifacts(test_dir)
    IO.puts("After cleanup, directory exists: #{File.exists?(test_dir)}")
  end

  @doc """
  Example 5: Staging environment with StagingConfigProvider
  """
  def example_staging_environment do
    IO.puts("=== Staging Environment ===")

    provider = StagingConfigProvider

    # Show feature flags
    flags = provider.get_feature_flags()
    IO.puts("Feature flags in staging:")

    for {flag, enabled} <- flags do
      status = if enabled, do: "✓ ENABLED", else: "✗ DISABLED"
      IO.puts("  - #{flag}: #{status}")
    end

    # Show database configuration
    db_config = provider.get_database_config()
    IO.puts("\nDatabase configuration:")
    IO.puts("  - Use production data copy: #{db_config.use_production_data_copy}")
    IO.puts("  - Anonymize sensitive data: #{db_config.anonymize_sensitive_data}")
    IO.puts("  - Auto refresh data: #{db_config.auto_refresh_data}")

    # Show deployment hours
    in_hours = provider.in_allowed_deployment_hours?()
    IO.puts("\nDeployment window:")
    IO.puts("  - Currently in allowed hours: #{in_hours}")
    IO.puts("  - Window: Monday-Friday, 8 AM - 8 PM UTC")

    # Show notification configuration
    notifications = provider.get_notification_config()
    IO.puts("\nNotifications:")
    IO.puts("  - Notify on deploy: #{notifications.notify_on_deploy}")
    IO.puts("  - Channels: #{inspect(notifications.notification_channels)}")
  end

  @doc """
  Example 6: Runtime provider switching
  """
  def example_runtime_switching do
    IO.puts("=== Runtime Provider Switching ===")

    # Show current provider
    original_provider = ConfigProviderFactory.get_provider()
    IO.puts("Original provider: #{inspect(original_provider)}")

    # Switch to development provider
    {:ok, message} = ConfigProviderFactory.switch_provider(DevelopmentConfigProvider)
    IO.puts("Switch result: #{message}")

    new_provider = ConfigProviderFactory.get_provider()
    IO.puts("New provider: #{inspect(new_provider)}")

    # Show different behavior
    dev_limits = new_provider.get_operation_limits()
    IO.puts("Development limits: #{dev_limits.download_timeout}ms timeout")

    # Switch back
    ConfigProviderFactory.switch_provider(original_provider)
    restored_provider = ConfigProviderFactory.get_provider()
    IO.puts("Restored provider: #{inspect(restored_provider)}")
  end

  @doc """
  Example 7: Integration with Orchestrator
  """
  def example_orchestrator_integration do
    IO.puts("=== Orchestrator Integration ===")

    # Use different providers with Orchestrator
    providers = [
      {"Development", DevelopmentConfigProvider},
      {"Testing", TestingConfigProvider},
      {"Staging", StagingConfigProvider}
    ]

    for {env_name, provider} <- providers do
      IO.puts("\n--- #{env_name} Environment ---")

      # Configure workflow with specific provider
      _workflow_config = [
        version: "3.4.17",
        source_path: "/tmp/example_#{String.downcase(env_name)}",
        plugins: [
          %{
            "version" => ~s["daisyui": "^4.12.23"],
            "statement" => ~s['daisyui': require('daisyui')]
          }
        ],
        build: false,
        deploy: false,
        config_provider: provider
      ]

      # Show how provider affects workflow
      limits = provider.get_operation_limits()
      policies = provider.get_build_policies()

      IO.puts("  - Download timeout: #{limits.download_timeout}ms")
      IO.puts("  - Allow experimental features: #{policies.allow_experimental_features}")
      IO.puts("  - Verbose logging: #{policies.verbose_logging}")

      # Validate operations
      download_result = provider.validate_operation_policy(:download, %{version: "3.4.17"})
      build_result = provider.validate_operation_policy(:build, %{version: "3.4.17"})

      IO.puts("  - Download policy: #{format_validation_result(download_result)}")
      IO.puts("  - Build policy: #{format_validation_result(build_result)}")
    end
  end

  @doc """
  Example 8: Custom configuration scenarios
  """
  def example_custom_scenarios do
    IO.puts("=== Custom Configuration Scenarios ===")

    # Scenario 1: High-security production
    IO.puts("\n1. High-Security Production:")
    prod_provider = ProductionConfigProvider
    security = prod_provider.get_security_config()

    IO.puts("  - Vulnerability scanning: #{security.scan_for_vulnerabilities}")
    IO.puts("  - SSL validation: #{security.validate_ssl_certificates}")
    IO.puts("  - Rate limiting: #{security.rate_limiting.requests_per_minute} req/min")

    # Scenario 2: Fast development iteration
    IO.puts("\n2. Fast Development Iteration:")
    dev_provider = DevelopmentConfigProvider
    cache = dev_provider.get_cache_config()

    IO.puts("  - Auto-invalidate cache: #{cache.auto_invalidate}")
    IO.puts("  - Cache builds: #{cache.cache_builds}")
    IO.puts("  - Max cache size: #{cache.max_cache_size_mb}MB")

    # Scenario 3: CI/CD pipeline
    IO.puts("\n3. CI/CD Pipeline:")
    test_provider = TestingConfigProvider
    ci = test_provider.get_ci_config()
    performance = test_provider.get_performance_config()

    IO.puts("  - Is CI: #{ci.is_ci}")
    IO.puts("  - CI provider: #{ci.ci_provider}")
    IO.puts("  - Parallel execution: #{performance.parallel_test_execution}")
    IO.puts("  - Max concurrency: #{performance.max_test_concurrency}")
  end

  @doc """
  Example 9: Provider validation and debugging
  """
  def example_provider_validation do
    IO.puts("=== Provider Validation ===")

    # List all available providers
    providers = ConfigProviderFactory.list_available_providers()
    IO.puts("Available providers: #{length(providers)}")

    for provider_info <- providers do
      IO.puts("\n#{provider_info.name} (#{provider_info.module})")
      IO.puts("  Description: #{provider_info.description}")
      IO.puts("  Environments: #{inspect(provider_info.environments)}")

      # Validate each provider
      case ConfigProviderFactory.validate_provider_config(provider_info.module) do
        {:ok, message} ->
          IO.puts("  Validation: ✓ #{message}")

        {:error, reason} ->
          IO.puts("  Validation: ✗ #{reason}")
      end

      # Get provider info
      info = ConfigProviderFactory.get_provider_info(provider_info.module)
      IO.puts("  Features: #{inspect(info.features)}")
      IO.puts("  Runtime config: #{info.supports_runtime_config}")
    end
  end

  @doc """
  Run all configuration examples
  """
  def run_all_examples do
    example_environment_selection()
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    example_development_workflow()
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    example_production_deployment()
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    example_testing_setup()
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    example_staging_environment()
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    example_runtime_switching()
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    example_orchestrator_integration()
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    example_custom_scenarios()
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    example_provider_validation()

    IO.puts("\n=== Configuration Provider Examples Complete ===")
    IO.puts("All examples demonstrate different aspects of environment-specific configuration.")
    IO.puts("Choose the provider that best fits your deployment environment and requirements.")
  end

  # Helper functions

  defp format_validation_result(:ok), do: "✓ ALLOWED"
  defp format_validation_result({:warning, msg}), do: "⚠ WARNING: #{msg}"
  defp format_validation_result({:error, {_type, msg}}), do: "✗ ERROR: #{msg}"
  defp format_validation_result({:error, msg}), do: "✗ ERROR: #{msg}"
end
