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
      # 10 seconds
      download_timeout: 10_000,
      # 30 seconds
      build_timeout: 30_000,
      # 50MB (smaller for tests)
      max_file_size: 50_000_000,
      # High concurrency for parallel tests
      max_concurrent_downloads: 10,
      # Minimal retries for fast failure
      retry_attempts: 1,
      # 1 minute cache (short for tests)
      cache_ttl: 60
    }
  end

  @impl true
  def get_deployment_config(target) do
    case target do
      :test ->
        %{
          destination: "/tmp/tailwind_test_builds",
          # Clean up after tests
          cleanup_after: true,
          # Skip validation for speed
          validate_binaries: false,
          # Skip manifest generation
          generate_manifest: false
        }

      :mock ->
        %{
          # In-memory deployment for testing
          destination: :memory,
          # Don't actually deploy
          simulate_only: true,
          # Track for test assertions
          track_operations: true
        }

      :ci ->
        %{
          destination: "./ci_artifacts",
          # Keep for CI artifact collection
          cleanup_after: false,
          # Validate in CI
          validate_binaries: true,
          generate_manifest: true,
          compress_artifacts: true
        }
    end
  end

  @impl true
  def get_build_policies do
    %{
      # Test-optimized build policies
      # Test experimental features
      allow_experimental_features: true,
      # Speed up tests
      skip_non_critical_validations: true,
      enable_debug_symbols: false,
      # Quiet for clean test output
      verbose_logging: false,
      # Fast parallel execution
      parallel_builds: true,
      # Full builds for deterministic tests
      incremental_builds: false,
      # Reproducible builds for tests
      deterministic_builds: true,
      # Use mocks when possible
      mock_external_tools: true
    }
  end

  @impl true
  def get_deployment_policies do
    %{
      # Testing deployment policies
      skip_production_checks: true,
      # Allow overwriting in tests
      allow_overwrite: true,
      # No backup needed for tests
      backup_existing: false,
      # No notifications in tests
      notify_on_deploy: false,
      # Clean up test artifacts
      auto_cleanup_old: true,
      # Keep minimal versions
      max_versions_kept: 3,
      # Track for test verification
      track_deployments: true
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
      # Minimal logging in tests
      level: :warning,
      enable_module_logging: false,
      log_http_requests: get_env_boolean(:log_http_in_tests, false),
      log_file_operations: false,
      log_compilation_steps: false,
      pretty_print: false,
      # Capture for test assertions
      capture_logs: true,
      # Don't write log files in tests
      log_to_file: false
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
      # No artificial delays in tests
      response_delay_ms: 0
    }
  end

  @doc """
  Get test performance configuration
  """
  def get_performance_config do
    %{
      parallel_test_execution: true,
      max_test_concurrency: System.schedulers_online(),
      # Process-level isolation
      test_isolation: :process,
      cleanup_between_tests: true,
      # 1GB memory limit for tests
      memory_limit_mb: 1000,
      # No timeout extension
      timeout_multiplier: 1.0
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
      # Disable by default for speed
      enable_property_testing: false,
      # Disable by default for speed
      fuzzing_enabled: false,
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
      # Usually disabled for speed
      performance_benchmarking: false,
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
      # Minimal logging in tests
      level: :warning,
      backends: [:console],
      # Sample all for test verification
      sample_rate: 1.0,
      # Very short retention
      trace_retention_hours: 1,
      detailed_logging: false,
      # Disabled for test speed
      performance_monitoring: false,
      error_tracking: :test,
      alert_on_errors: false,
      alert_on_high_latency: false,
      metrics_collection: %{
        system_metrics: false,
        business_metrics: false,
        # For performance regression testing
        performance_metrics: true,
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
