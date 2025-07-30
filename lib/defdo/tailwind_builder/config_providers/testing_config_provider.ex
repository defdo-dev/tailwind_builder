defmodule Defdo.TailwindBuilder.ConfigProviders.TestingConfigProvider do
  @moduledoc """
  ConfigProvider optimized for testing and CI/CD environments.
  
  Features:
  - Fast, deterministic configurations for testing
  - Mock-friendly settings for isolated testing
  - Minimal external dependencies
  - Predictable behavior for automated testing
  - Support for test fixtures and mocks
  """
  
  @behaviour Defdo.TailwindBuilder.ConfigProvider

  # Minimal plugin set for testing
  @testing_supported_plugins %{
    "daisyui" => %{
      "version" => ~s["daisyui": "^4.12.23"],
      "statement" => ~s['daisyui': require('daisyui')],
      "description" => "Test plugin for Tailwind CSS",
      "npm_name" => "daisyui",
      "compatible_versions" => ["3.x", "4.x"]
    },
    "test-plugin" => %{
      "version" => ~s["test-plugin": "^1.0.0"],
      "statement" => ~s['test-plugin': require('test-plugin')],
      "description" => "Mock plugin for testing",
      "npm_name" => "test-plugin",
      "compatible_versions" => ["3.x", "4.x"]
    }
  }

  # Test checksums (including known test values)
  @testing_checksums %{
    "3.4.17" => "89c0a7027449cbe564f8722e84108f7bfa0224b5d9289c47cc967ffef8e1b016",
    "4.0.9" => "7c36fdcdfed4d1b690a56a1267457a8ac9c640ccae2efcaed59f5053d330000a",
    "4.0.17" => "3590bcb90a75c32ba8b10d692d26838caedbc267a57db23931694abc9598c873",
    "4.1.11" => "149b7db8417a4a0419ada1d2dc428a11202fc6b971f037b7a8527371c59e0cae",
    # Test-specific versions
    "test-version-1.0.0" => "test_checksum_deterministic_value",
    "mock-version-2.0.0" => "mock_checksum_for_testing"
  }

  @impl true
  def get_supported_plugins do
    # Allow override for specific test scenarios
    Application.get_env(:tailwind_builder, :test_plugins, @testing_supported_plugins)
  end

  @impl true  
  def get_known_checksums do
    Application.get_env(:tailwind_builder, :test_checksums, @testing_checksums)
  end

  @impl true
  def get_version_policy(version) do
    cond do
      # Allow test versions
      String.starts_with?(version, "test-") or String.starts_with?(version, "mock-") ->
        :allowed
      
      # Allow all known versions for testing
      Map.has_key?(@testing_checksums, version) ->
        :allowed
      
      # Allow unknown versions in test mode (for error testing)
      true ->
        :allowed
    end
  end

  @impl true
  def get_operation_limits do
    %{
      # Fast timeouts for quick test execution
      download_timeout: 10_000,       # 10 seconds
      build_timeout: 30_000,          # 30 seconds
      max_file_size: 50_000_000,      # 50MB (smaller for tests)
      max_concurrent_downloads: 10,   # High concurrency for parallel tests
      retry_attempts: 1,              # Minimal retries for fast failure
      cache_ttl: 60                   # 1 minute cache (short for tests)
    }
  end

  @impl true
  def get_deployment_config(target) do
    case target do
      :test ->
        %{
          destination: "/tmp/tailwind_test_builds",
          cleanup_after: true,         # Clean up after tests
          validate_binaries: false,    # Skip validation for speed
          generate_manifest: false     # Skip manifest generation
        }
      
      :mock ->
        %{
          destination: :memory,        # In-memory deployment for testing
          simulate_only: true,         # Don't actually deploy
          track_operations: true       # Track for test assertions
        }
      
      :ci ->
        %{
          destination: "./ci_artifacts",
          cleanup_after: false,        # Keep for CI artifact collection
          validate_binaries: true,     # Validate in CI
          generate_manifest: true,
          compress_artifacts: true
        }
    end
  end

  @impl true
  def get_build_policies do
    %{
      # Test-optimized build policies
      allow_experimental_features: true,   # Test experimental features
      skip_non_critical_validations: true, # Speed up tests
      enable_debug_symbols: false,
      verbose_logging: false,              # Quiet for clean test output
      parallel_builds: true,               # Fast parallel execution
      incremental_builds: false,           # Full builds for deterministic tests
      deterministic_builds: true,          # Reproducible builds for tests
      mock_external_tools: true            # Use mocks when possible
    }
  end

  @impl true
  def get_deployment_policies do
    %{
      # Testing deployment policies
      skip_production_checks: true,
      allow_overwrite: true,          # Allow overwriting in tests
      backup_existing: false,         # No backup needed for tests
      notify_on_deploy: false,        # No notifications in tests
      auto_cleanup_old: true,         # Clean up test artifacts
      max_versions_kept: 3,           # Keep minimal versions
      track_deployments: true         # Track for test verification
    }
  end

  @impl true
  def validate_operation_policy(operation, context)

  def validate_operation_policy(:download, %{version: _version}) do
    # Always allow downloads in test mode
    :ok
  end

  def validate_operation_policy(:build, %{version: _version}) do
    # Always allow builds in test mode
    :ok
  end

  def validate_operation_policy(:deploy, %{target: _target}) do
    # Always allow deployments in test mode
    :ok
  end

  def validate_operation_policy(:cross_compile, %{version: _version}) do
    # Always allow cross-compilation in test mode
    :ok
  end

  def validate_operation_policy(_operation, _context) do
    # Default case: allow all operations in test mode
    :ok
  end

  # Testing-specific helpers

  @doc """
  Get test-specific logging configuration
  """
  def get_logging_config do
    %{
      level: :warning,               # Minimal logging in tests
      enable_module_logging: false,
      log_http_requests: get_env_boolean(:log_http_in_tests, false),
      log_file_operations: false,
      log_compilation_steps: false,
      pretty_print: false,
      capture_logs: true,            # Capture for test assertions
      log_to_file: false            # Don't write log files in tests
    }
  end

  @doc """
  Get test fixture configuration
  """
  def get_fixture_config do
    %{
      fixtures_directory: "test/fixtures",
      mock_downloads: true,
      mock_external_apis: true,
      use_cached_responses: true,
      deterministic_responses: true,
      fixture_data: %{
        tailwind_versions: ["3.4.17", "4.0.9", "4.1.11"],
        plugin_versions: %{
          "daisyui" => ["4.12.23", "5.0.49"],
          "test-plugin" => ["1.0.0", "2.0.0"]
        }
      }
    }
  end

  @doc """
  Get mock service configuration
  """
  def get_mock_config do
    %{
      mock_http_client: true,
      mock_file_system: get_env_boolean(:mock_filesystem, false),
      mock_external_tools: true,
      mock_npm_registry: true,
      mock_github_api: true,
      predictable_responses: true,
      response_delay_ms: 0           # No artificial delays in tests
    }
  end

  @doc """
  Get test performance configuration
  """
  def get_performance_config do
    %{
      parallel_test_execution: true,
      max_test_concurrency: System.schedulers_online(),
      test_isolation: :process,      # Process-level isolation
      cleanup_between_tests: true,
      memory_limit_mb: 1000,        # 1GB memory limit for tests
      timeout_multiplier: 1.0       # No timeout extension
    }
  end

  @doc """
  Get test assertion helpers configuration
  """
  def get_assertion_config do
    %{
      enable_detailed_diffs: true,
      capture_intermediate_states: true,
      track_operation_history: true,
      enable_property_testing: false,  # Disable by default for speed
      fuzzing_enabled: false,          # Disable by default for speed
      regression_testing: true
    }
  end

  @doc """
  Check if running in test mode
  """
  def test_mode? do
    Mix.env() == :test or Application.get_env(:tailwind_builder, :force_test_mode, false)
  end

  @doc """
  Get CI-specific configuration
  """
  def get_ci_config do
    %{
      is_ci: System.get_env("CI") == "true",
      ci_provider: detect_ci_provider(),
      artifact_collection: true,
      coverage_reporting: true,
      performance_benchmarking: false, # Usually disabled for speed
      matrix_testing: true,
      cache_ci_dependencies: true,
      parallel_jobs: get_ci_parallel_jobs()
    }
  end

  @doc """
  Create a test-specific temporary directory
  """
  def create_test_directory(prefix \\ "tailwind_test") do
    timestamp = System.system_time(:nanosecond)
    test_dir = "/tmp/#{prefix}_#{timestamp}"
    File.mkdir_p!(test_dir)
    test_dir
  end

  @doc """
  Clean up test artifacts
  """
  def cleanup_test_artifacts(directories) when is_list(directories) do
    for dir <- directories do
      if File.exists?(dir) do
        File.rm_rf!(dir)
      end
    end
  end

  def cleanup_test_artifacts(directory) when is_binary(directory) do
    cleanup_test_artifacts([directory])
  end

  # Private helpers

  defp get_env_boolean(key, default) do
    case Application.get_env(:tailwind_builder, key, default) do
      val when is_boolean(val) -> val
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp detect_ci_provider do
    cond do
      System.get_env("GITHUB_ACTIONS") -> :github_actions
      System.get_env("GITLAB_CI") -> :gitlab_ci
      System.get_env("CIRCLECI") -> :circle_ci
      System.get_env("TRAVIS") -> :travis_ci
      System.get_env("JENKINS_URL") -> :jenkins
      true -> :unknown
    end
  end

  defp get_ci_parallel_jobs do
    case System.get_env("CI_PARALLEL_JOBS") do
      nil -> System.schedulers_online()
      jobs -> String.to_integer(jobs)
    end
  end

  @doc """
  Get testing telemetry configuration
  """
  def get_telemetry_config do
    %{
      enabled: true,
      level: :warning,  # Minimal logging in tests
      backends: [:console],
      sample_rate: 1.0,  # Sample all for test verification
      trace_retention_hours: 1,  # Very short retention
      detailed_logging: false,
      performance_monitoring: false,  # Disabled for test speed
      error_tracking: :test,
      alert_on_errors: false,
      alert_on_high_latency: false,
      metrics_collection: %{
        system_metrics: false,
        business_metrics: false,
        performance_metrics: true,  # For performance regression testing
        test_metrics: true
      },
      test_integration: %{
        capture_test_metrics: true,
        track_test_duration: true,
        track_assertion_counts: true,
        memory_leak_detection: true
      }
    }
  end
end