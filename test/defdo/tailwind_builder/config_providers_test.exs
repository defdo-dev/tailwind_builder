defmodule Defdo.TailwindBuilder.ConfigProvidersTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindBuilder.ConfigProviders.{
    DevelopmentConfigProvider,
    ProductionConfigProvider,
    StagingConfigProvider,
    TestingConfigProvider
  }

  @moduletag :config_providers

  describe "DevelopmentConfigProvider" do
    test "has extensive plugin support" do
      plugins = DevelopmentConfigProvider.get_supported_plugins()

      assert is_map(plugins)
      assert Map.has_key?(plugins, "daisyui")
      assert Map.has_key?(plugins, "@tailwindcss/typography")
      assert Map.has_key?(plugins, "@tailwindcss/forms")
      assert Map.has_key?(plugins, "tailwindcss-animate")

      # Should have more plugins than production
      prod_plugins = ProductionConfigProvider.get_supported_plugins()
      assert map_size(plugins) > map_size(prod_plugins)
    end

    test "allows experimental versions" do
      # Should allow beta/alpha versions
      assert DevelopmentConfigProvider.get_version_policy("4.2.0-beta.1") == :allowed
      assert DevelopmentConfigProvider.get_version_policy("3.5.0-alpha.1") == :allowed

      # Should allow unknown versions for experimentation
      assert DevelopmentConfigProvider.get_version_policy("99.99.99") == :allowed
    end

    test "has fast operation limits" do
      limits = DevelopmentConfigProvider.get_operation_limits()

      # 30 seconds
      assert limits.download_timeout == 30_000
      # 2 minutes
      assert limits.build_timeout == 120_000
      assert limits.max_concurrent_downloads == 5
      assert limits.retry_attempts == 2
    end

    test "has development-specific configurations" do
      # Test logging config
      logging = DevelopmentConfigProvider.get_logging_config()
      assert logging.level == :debug
      assert logging.enable_module_logging == true
      assert logging.pretty_print == true

      # Test cache config
      cache = DevelopmentConfigProvider.get_cache_config()
      # Don't cache builds in development
      assert cache.cache_builds == false
      assert cache.auto_invalidate == true
    end

    test "validates policies permissively" do
      # Should allow all downloads
      assert DevelopmentConfigProvider.validate_operation_policy(:download, %{version: "3.4.17"}) ==
               :ok

      assert DevelopmentConfigProvider.validate_operation_policy(:download, %{version: "unknown"}) ==
               :ok

      # Should allow all builds
      assert DevelopmentConfigProvider.validate_operation_policy(:build, %{version: "4.1.11"}) ==
               :ok
    end

    test "provides development utilities" do
      assert DevelopmentConfigProvider.development_mode?() in [true, false]

      testing_config = DevelopmentConfigProvider.get_testing_config()
      assert testing_config.preserve_test_artifacts == true
    end
  end

  describe "ProductionConfigProvider" do
    test "has limited, stable plugin support" do
      plugins = ProductionConfigProvider.get_supported_plugins()

      assert is_map(plugins)
      assert Map.has_key?(plugins, "daisyui")
      assert Map.has_key?(plugins, "@tailwindcss/typography")

      # Should NOT have experimental plugins
      refute Map.has_key?(plugins, "tailwindcss-animate")
      refute Map.has_key?(plugins, "@tailwindcss/forms")
    end

    test "blocks unstable versions" do
      # Should block beta/alpha versions
      assert ProductionConfigProvider.get_version_policy("4.2.0-beta.1") == :blocked
      assert ProductionConfigProvider.get_version_policy("3.5.0-alpha.1") == :blocked

      # Should block unknown versions
      assert ProductionConfigProvider.get_version_policy("99.99.99") == :blocked

      # Should allow stable versions
      assert ProductionConfigProvider.get_version_policy("3.4.17") == :allowed
    end

    test "has conservative operation limits" do
      limits = ProductionConfigProvider.get_operation_limits()

      # 2 minutes
      assert limits.download_timeout == 120_000
      # 10 minutes
      assert limits.build_timeout == 600_000
      assert limits.max_concurrent_downloads == 2
      assert limits.retry_attempts == 5
    end

    test "has production-specific configurations" do
      # Test logging config
      logging = ProductionConfigProvider.get_logging_config()
      assert logging.level == :info
      assert logging.enable_module_logging == false
      assert logging.structured_logging == true

      # Test security config
      security = ProductionConfigProvider.get_security_config()
      assert security.validate_all_checksums == true
      assert security.enforce_https == true

      # Test monitoring config
      monitoring = ProductionConfigProvider.get_monitoring_config()
      assert monitoring.enable_metrics == true
      assert monitoring.alert_on_errors == true
    end

    test "validates policies strictly" do
      # Should allow only approved versions
      assert ProductionConfigProvider.validate_operation_policy(:download, %{version: "3.4.17"}) ==
               :ok

      result = ProductionConfigProvider.validate_operation_policy(:download, %{version: "4.0.9"})
      assert {:error, {:version_blocked, _}} = result

      # Should block local deployments
      result = ProductionConfigProvider.validate_operation_policy(:deploy, %{target: :local})
      assert {:error, {:deploy_blocked, _}} = result
    end

    test "provides production utilities" do
      assert ProductionConfigProvider.production_mode?() in [true, false]
      assert is_boolean(ProductionConfigProvider.in_deployment_window?())

      backup_config = ProductionConfigProvider.get_backup_config()
      assert backup_config.enable_automatic_backups == true
    end
  end

  describe "StagingConfigProvider" do
    test "has moderate plugin support" do
      plugins = StagingConfigProvider.get_supported_plugins()

      assert is_map(plugins)
      assert Map.has_key?(plugins, "daisyui")
      assert Map.has_key?(plugins, "@tailwindcss/typography")
      assert Map.has_key?(plugins, "@tailwindcss/forms")

      # Should have more than production but may be less than development
      prod_plugins = ProductionConfigProvider.get_supported_plugins()
      assert map_size(plugins) >= map_size(prod_plugins)
    end

    test "allows release candidates" do
      # Should allow release candidates
      assert StagingConfigProvider.get_version_policy("4.2.0-rc.1") == :allowed

      # Should allow stable versions
      assert StagingConfigProvider.get_version_policy("3.4.17") == :allowed

      # Should block unknown versions (more restrictive than development)
      assert StagingConfigProvider.get_version_policy("99.99.99") == :blocked
    end

    test "has balanced operation limits" do
      limits = StagingConfigProvider.get_operation_limits()

      # 1.5 minutes
      assert limits.download_timeout == 90_000
      # 5 minutes
      assert limits.build_timeout == 300_000
      assert limits.max_concurrent_downloads == 3
      assert limits.retry_attempts == 3
    end

    test "has staging-specific configurations" do
      # Test feature flags
      flags = StagingConfigProvider.get_feature_flags()
      assert is_map(flags)
      assert Map.has_key?(flags, :enable_advanced_caching)

      # Test database config
      db_config = StagingConfigProvider.get_database_config()
      assert db_config.use_production_data_copy == true
      assert db_config.anonymize_sensitive_data == true
    end

    test "validates policies moderately" do
      # Should allow approved versions
      assert StagingConfigProvider.validate_operation_policy(:download, %{version: "3.4.17"}) ==
               :ok

      # Should allow staging deployments
      assert StagingConfigProvider.validate_operation_policy(:deploy, %{target: :staging}) == :ok

      # Should warn on local deployments
      result = StagingConfigProvider.validate_operation_policy(:deploy, %{target: :local})
      assert {:warning, _} = result
    end

    test "provides staging utilities" do
      assert StagingConfigProvider.staging_mode?() in [true, false]
      assert is_boolean(StagingConfigProvider.in_allowed_deployment_hours?())

      notification_config = StagingConfigProvider.get_notification_config()
      assert notification_config.notify_on_deploy == true
    end
  end

  describe "TestingConfigProvider" do
    test "has minimal plugin support for testing" do
      plugins = TestingConfigProvider.get_supported_plugins()

      assert is_map(plugins)
      assert Map.has_key?(plugins, "daisyui")
      # Special test plugin
      assert Map.has_key?(plugins, "test-plugin")
    end

    test "allows all versions for testing" do
      # Should allow test versions
      assert TestingConfigProvider.get_version_policy("test-version-1.0.0") == :allowed
      assert TestingConfigProvider.get_version_policy("mock-version-2.0.0") == :allowed

      # Should allow unknown versions for error testing
      assert TestingConfigProvider.get_version_policy("99.99.99") == :allowed
    end

    test "has fast operation limits for quick testing" do
      limits = TestingConfigProvider.get_operation_limits()

      # 10 seconds
      assert limits.download_timeout == 10_000
      # 30 seconds
      assert limits.build_timeout == 30_000
      assert limits.max_concurrent_downloads == 10
      assert limits.retry_attempts == 1
    end

    test "has testing-specific configurations" do
      # Test fixture config
      fixtures = TestingConfigProvider.get_fixture_config()
      assert fixtures.mock_downloads == true
      assert fixtures.deterministic_responses == true

      # Test mock config
      mocks = TestingConfigProvider.get_mock_config()
      assert mocks.mock_http_client == true
      assert mocks.response_delay_ms == 0
    end

    test "validates policies permissively for testing" do
      # Should allow all operations
      assert TestingConfigProvider.validate_operation_policy(:download, %{version: "any"}) == :ok
      assert TestingConfigProvider.validate_operation_policy(:build, %{version: "any"}) == :ok
      assert TestingConfigProvider.validate_operation_policy(:deploy, %{target: :any}) == :ok
    end

    test "provides testing utilities" do
      assert TestingConfigProvider.test_mode?() in [true, false]

      # Test directory creation
      test_dir = TestingConfigProvider.create_test_directory("test_prefix")
      assert String.starts_with?(test_dir, "/tmp/test_prefix_")
      assert File.exists?(test_dir)

      # Test cleanup
      TestingConfigProvider.cleanup_test_artifacts(test_dir)
      refute File.exists?(test_dir)

      # Test CI config
      ci_config = TestingConfigProvider.get_ci_config()
      assert is_boolean(ci_config.is_ci)
      assert is_atom(ci_config.ci_provider)
    end
  end

  describe "behavior compliance" do
    @providers [
      DevelopmentConfigProvider,
      ProductionConfigProvider,
      StagingConfigProvider,
      TestingConfigProvider
    ]

    test "all providers implement required behavior functions" do
      for provider <- @providers do
        # Required functions from ConfigProvider behavior
        assert function_exported?(provider, :get_supported_plugins, 0)
        assert function_exported?(provider, :get_known_checksums, 0)
        assert function_exported?(provider, :get_version_policy, 1)
        assert function_exported?(provider, :get_operation_limits, 0)
        assert function_exported?(provider, :get_deployment_config, 1)
        assert function_exported?(provider, :get_build_policies, 0)
        assert function_exported?(provider, :get_deployment_policies, 0)
        assert function_exported?(provider, :validate_operation_policy, 2)
      end
    end

    test "all providers return valid data structures" do
      for provider <- @providers do
        # Test basic function calls return expected types
        plugins = provider.get_supported_plugins()
        assert is_map(plugins)

        checksums = provider.get_known_checksums()
        assert is_map(checksums)

        policy = provider.get_version_policy("3.4.17")
        assert policy in [:allowed, :deprecated, :blocked]

        limits = provider.get_operation_limits()
        assert is_map(limits)
        assert is_integer(limits.download_timeout)
        assert is_integer(limits.build_timeout)

        deployment_config = provider.get_deployment_config(:test)
        assert is_map(deployment_config)

        build_policies = provider.get_build_policies()
        assert is_map(build_policies)

        deployment_policies = provider.get_deployment_policies()
        assert is_map(deployment_policies)
      end
    end

    test "providers have different characteristics" do
      dev_limits = DevelopmentConfigProvider.get_operation_limits()
      prod_limits = ProductionConfigProvider.get_operation_limits()
      test_limits = TestingConfigProvider.get_operation_limits()

      # Development should be faster than production
      assert dev_limits.download_timeout < prod_limits.download_timeout

      # Testing should be fastest
      assert test_limits.download_timeout <= dev_limits.download_timeout
      assert test_limits.retry_attempts <= dev_limits.retry_attempts

      # Production should have most retries
      assert prod_limits.retry_attempts >= dev_limits.retry_attempts
    end
  end

  describe "environment-specific features" do
    test "development provider supports development workflows" do
      # Should have debugging features
      logging = DevelopmentConfigProvider.get_logging_config()
      assert logging.level == :debug
      assert logging.log_http_requests == true

      # Should have flexible caching
      cache = DevelopmentConfigProvider.get_cache_config()
      assert cache.auto_invalidate == true
      assert cache.cache_builds == false
    end

    test "production provider enforces production standards" do
      # Should have security features
      security = ProductionConfigProvider.get_security_config()
      assert security.validate_all_checksums == true
      assert security.scan_for_vulnerabilities == true

      # Should have monitoring
      monitoring = ProductionConfigProvider.get_monitoring_config()
      assert monitoring.enable_metrics == true
      assert monitoring.alert_on_errors == true
    end

    test "testing provider optimizes for test execution" do
      # Should have mock configurations
      mocks = TestingConfigProvider.get_mock_config()
      assert mocks.mock_http_client == true
      assert mocks.predictable_responses == true

      # Should have performance optimizations
      perf = TestingConfigProvider.get_performance_config()
      assert perf.parallel_test_execution == true
      assert perf.timeout_multiplier == 1.0
    end

    test "staging provider balances production and development needs" do
      # Should have feature flags for controlled testing
      flags = StagingConfigProvider.get_feature_flags()
      assert is_map(flags)

      # Should have production-like data handling
      db_config = StagingConfigProvider.get_database_config()
      assert db_config.use_production_data_copy == true
      assert db_config.anonymize_sensitive_data == true
    end
  end
end
