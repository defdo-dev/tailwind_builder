defmodule Defdo.TailwindBuilder.ConfigProviderFactoryTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindBuilder.ConfigProviderFactory

  alias Defdo.TailwindBuilder.ConfigProviders.{
    DevelopmentConfigProvider,
    ProductionConfigProvider,
    StagingConfigProvider,
    TestingConfigProvider
  }

  alias Defdo.TailwindBuilder.DefaultConfigProvider

  @moduletag :config_provider

  describe "get_provider/1" do
    test "returns default provider when no override specified" do
      # Clear any existing config
      original_config = Application.get_env(:tailwind_builder, :config_provider)
      Application.delete_env(:tailwind_builder, :config_provider)

      try do
        provider = ConfigProviderFactory.get_provider()
        # Depends on Mix.env
        assert provider in [TestingConfigProvider, DefaultConfigProvider]
      after
        # Restore original config
        if original_config do
          Application.put_env(:tailwind_builder, :config_provider, original_config)
        end
      end
    end

    test "returns configured provider when explicitly set" do
      original_config = Application.get_env(:tailwind_builder, :config_provider)
      Application.put_env(:tailwind_builder, :config_provider, ProductionConfigProvider)

      try do
        provider = ConfigProviderFactory.get_provider()
        assert provider == ProductionConfigProvider
      after
        if original_config do
          Application.put_env(:tailwind_builder, :config_provider, original_config)
        else
          Application.delete_env(:tailwind_builder, :config_provider)
        end
      end
    end

    test "returns correct provider for environment symbols" do
      assert ConfigProviderFactory.get_provider(:development) == DevelopmentConfigProvider
      assert ConfigProviderFactory.get_provider(:dev) == DevelopmentConfigProvider
      assert ConfigProviderFactory.get_provider(:production) == ProductionConfigProvider
      assert ConfigProviderFactory.get_provider(:staging) == StagingConfigProvider
      assert ConfigProviderFactory.get_provider(:stage) == StagingConfigProvider
      assert ConfigProviderFactory.get_provider(:test) == TestingConfigProvider
      assert ConfigProviderFactory.get_provider(:testing) == TestingConfigProvider
      assert ConfigProviderFactory.get_provider(:default) == DefaultConfigProvider
    end

    test "raises error for invalid provider" do
      assert_raise ArgumentError, fn ->
        ConfigProviderFactory.get_provider(:invalid)
      end
    end

    test "validates provider module implements behavior" do
      # Should work with valid provider
      assert ConfigProviderFactory.get_provider(TestingConfigProvider) == TestingConfigProvider

      # Should fail with invalid provider
      assert_raise ArgumentError, ~r/does not implement ConfigProvider behavior/, fn ->
        ConfigProviderFactory.get_provider(String)
      end
    end
  end

  describe "auto_detect_provider/0" do
    test "detects provider based on environment variables" do
      # Test production detection
      System.put_env("TAILWIND_BUILDER_ENV", "production")

      try do
        assert ConfigProviderFactory.auto_detect_provider() == ProductionConfigProvider
      after
        System.delete_env("TAILWIND_BUILDER_ENV")
      end

      # Test staging detection  
      System.put_env("TAILWIND_BUILDER_ENV", "staging")

      try do
        assert ConfigProviderFactory.auto_detect_provider() == StagingConfigProvider
      after
        System.delete_env("TAILWIND_BUILDER_ENV")
      end
    end

    test "detects CI environment" do
      System.put_env("CI", "true")

      try do
        assert ConfigProviderFactory.auto_detect_provider() == TestingConfigProvider
      after
        System.delete_env("CI")
      end
    end

    test "falls back to Mix environment" do
      # In test environment, should return TestingConfigProvider
      # (assuming this test runs in test environment)
      provider = ConfigProviderFactory.auto_detect_provider()
      assert provider == TestingConfigProvider
    end
  end

  describe "get_provider_info/1" do
    test "returns comprehensive provider information" do
      info = ConfigProviderFactory.get_provider_info(TestingConfigProvider)

      assert info.module == TestingConfigProvider
      assert info.environment == :testing
      assert is_list(info.features)
      assert is_list(info.config_keys)
      assert is_boolean(info.supports_runtime_config)
      assert is_binary(info.version) or info.version == "unknown"
    end

    test "returns info for current provider when no argument given" do
      info = ConfigProviderFactory.get_provider_info()

      assert is_atom(info.module)
      assert is_atom(info.environment)
      assert is_list(info.features)
    end
  end

  describe "list_available_providers/0" do
    test "returns list of all available providers" do
      providers = ConfigProviderFactory.list_available_providers()

      assert is_list(providers)
      # At least the 5 we created
      assert length(providers) >= 5

      # Check that each provider has required fields
      for provider <- providers do
        assert Map.has_key?(provider, :module)
        assert Map.has_key?(provider, :name)
        assert Map.has_key?(provider, :description)
        assert Map.has_key?(provider, :environments)
        assert is_atom(provider.module)
        assert is_binary(provider.name)
        assert is_binary(provider.description)
        assert is_list(provider.environments)
      end

      # Check that our known providers are included
      modules = Enum.map(providers, & &1.module)
      assert DefaultConfigProvider in modules
      assert DevelopmentConfigProvider in modules
      assert ProductionConfigProvider in modules
      assert StagingConfigProvider in modules
      assert TestingConfigProvider in modules
    end
  end

  describe "validate_provider_config/1" do
    test "validates valid providers" do
      assert {:ok, _message} =
               ConfigProviderFactory.validate_provider_config(TestingConfigProvider)

      assert {:ok, _message} =
               ConfigProviderFactory.validate_provider_config(DefaultConfigProvider)

      assert {:ok, _message} =
               ConfigProviderFactory.validate_provider_config(DevelopmentConfigProvider)
    end

    test "validates current provider when no argument given" do
      result = ConfigProviderFactory.validate_provider_config()
      assert {:ok, _message} = result
    end

    test "returns error for invalid provider" do
      assert {:error, _reason} = ConfigProviderFactory.validate_provider_config(String)
    end
  end

  describe "switch_provider/1" do
    test "switches to valid provider" do
      original_provider = ConfigProviderFactory.get_provider()

      try do
        assert {:ok, _message} = ConfigProviderFactory.switch_provider(DevelopmentConfigProvider)
        assert ConfigProviderFactory.get_provider() == DevelopmentConfigProvider
      after
        # Restore original provider
        ConfigProviderFactory.switch_provider(original_provider)
      end
    end

    test "rejects invalid provider" do
      assert {:error, _reason} = ConfigProviderFactory.switch_provider(String)
    end
  end

  describe "create_provider/2" do
    test "creates module instance by default" do
      provider = ConfigProviderFactory.create_provider(TestingConfigProvider)
      assert provider == TestingConfigProvider
    end

    test "creates module instance explicitly" do
      provider =
        ConfigProviderFactory.create_provider(TestingConfigProvider, instance_type: :module)

      assert provider == TestingConfigProvider
    end
  end

  describe "integration with actual providers" do
    test "all providers implement required behavior functions" do
      providers = [
        DefaultConfigProvider,
        DevelopmentConfigProvider,
        ProductionConfigProvider,
        StagingConfigProvider,
        TestingConfigProvider
      ]

      for provider <- providers do
        # Test that all required functions exist and can be called
        assert is_map(provider.get_supported_plugins())
        assert is_map(provider.get_known_checksums())
        assert provider.get_version_policy("3.4.17") in [:allowed, :deprecated, :blocked]
        assert is_map(provider.get_operation_limits())
        assert is_map(provider.get_deployment_config(:test))
        assert is_map(provider.get_build_policies())
        assert is_map(provider.get_deployment_policies())

        # Test validation function
        result = provider.validate_operation_policy(:download, %{version: "3.4.17"})

        case result do
          :ok -> assert true
          {:warning, _msg} -> assert true
          {:error, _reason} -> assert true
          _ -> flunk("Unexpected validation result: #{inspect(result)}")
        end
      end
    end

    test "providers have different configurations" do
      dev_plugins = DevelopmentConfigProvider.get_supported_plugins()
      prod_plugins = ProductionConfigProvider.get_supported_plugins()

      # Development should have more plugins than production
      assert map_size(dev_plugins) >= map_size(prod_plugins)

      # Test operation limits are different
      dev_limits = DevelopmentConfigProvider.get_operation_limits()
      prod_limits = ProductionConfigProvider.get_operation_limits()

      # Development should have faster timeouts than production
      assert dev_limits.download_timeout <= prod_limits.download_timeout
    end

    test "provider-specific features work correctly" do
      # Test development-specific features
      if function_exported?(DevelopmentConfigProvider, :development_mode?, 0) do
        assert is_boolean(DevelopmentConfigProvider.development_mode?())
      end

      if function_exported?(DevelopmentConfigProvider, :get_logging_config, 0) do
        assert is_map(DevelopmentConfigProvider.get_logging_config())
      end

      # Test production-specific features
      if function_exported?(ProductionConfigProvider, :production_mode?, 0) do
        assert is_boolean(ProductionConfigProvider.production_mode?())
      end

      if function_exported?(ProductionConfigProvider, :in_deployment_window?, 0) do
        assert is_boolean(ProductionConfigProvider.in_deployment_window?())
      end

      # Test staging-specific features
      if function_exported?(StagingConfigProvider, :staging_mode?, 0) do
        assert is_boolean(StagingConfigProvider.staging_mode?())
      end

      if function_exported?(StagingConfigProvider, :get_feature_flags, 0) do
        assert is_map(StagingConfigProvider.get_feature_flags())
      end

      # Test testing-specific features
      if function_exported?(TestingConfigProvider, :test_mode?, 0) do
        assert is_boolean(TestingConfigProvider.test_mode?())
      end

      if function_exported?(TestingConfigProvider, :create_test_directory, 1) do
        test_dir = TestingConfigProvider.create_test_directory("test")
        assert File.exists?(test_dir)
        TestingConfigProvider.cleanup_test_artifacts(test_dir)
      end
    end
  end
end
