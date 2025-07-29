defmodule Defdo.TailwindBuilderOrchestratorIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Defdo.TailwindBuilder.{
    Orchestrator,
    DefaultConfigProvider
  }

  @moduletag :orchestrator_integration
  @moduletag :capture_log

  setup do
    test_id = System.unique_integer([:positive])
    temp_dir = "/tmp/orchestrator_test_#{test_id}"
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    %{temp_dir: temp_dir}
  end

  describe "Orchestrator workflow integration" do
    @tag :full_workflow
    test "orchestrator executes complete workflow successfully", %{temp_dir: temp_dir} do
      workflow_config = [
        version: "3.4.17",
        source_path: temp_dir,
        plugins: [
          %{
            "version" => ~s["daisyui": "^4.12.23"],
            "statement" => ~s['daisyui': require('daisyui')]
          }
        ],
        build: false,  # Skip actual build for integration test
        deploy: false, # Skip actual deploy for integration test
        config_provider: DefaultConfigProvider,
        validate_checksums: true
      ]

      capture_log(fn ->
        assert {:ok, result} = Orchestrator.execute_workflow(workflow_config)
        
        # Verify workflow completion
        assert result.download_completed == true
        assert result.plugins_applied > 0
        assert result.version == "3.4.17"
        assert is_binary(result.completion_time)
        
        # Verify files were created
        extracted_path = Path.join([temp_dir, "tailwindcss-3.4.17"])
        assert File.exists?(extracted_path)
      end)
    end

    @tag :workflow_with_validation
    test "orchestrator validates each step before proceeding", %{temp_dir: temp_dir} do
      # Test with a workflow that should validate each step
      workflow_config = [
        version: "4.1.11",
        source_path: temp_dir,
        plugins: [],  # No plugins to test validation
        build: false,
        deploy: false,
        config_provider: DefaultConfigProvider,
        validate_at_each_step: true
      ]

      assert {:ok, result} = Orchestrator.execute_workflow(workflow_config)
      
      # Should have validation results for each step
      assert Map.has_key?(result, :validation_results)
      assert result.validation_results.download == :ok
      assert result.validation_results.plugins == :ok
    end

    @tag :workflow_error_handling
    test "orchestrator handles errors gracefully and provides diagnostics", %{temp_dir: temp_dir} do
      # Test with invalid version to trigger error
      workflow_config = [
        version: "999.999.999",
        source_path: temp_dir,
        plugins: [],
        build: false,
        deploy: false,
        config_provider: DefaultConfigProvider
      ]

      assert {:error, {step, error_details}} = Orchestrator.execute_workflow(workflow_config)
      
      # Should fail at download step with descriptive error
      assert step == :download
      assert is_map(error_details) or is_atom(error_details) or is_tuple(error_details)
    end

    @tag :workflow_partial_success
    test "orchestrator continues after non-critical failures", %{temp_dir: temp_dir} do
      # Test workflow with invalid plugin but valid download
      workflow_config = [
        version: "3.4.17",
        source_path: temp_dir,
        plugins: [
          %{
            "version" => ~s["daisyui": "^4.12.23"],
            "statement" => ~s['daisyui': require('daisyui')]
          },
          %{
            "invalid" => "plugin spec"  # This should fail
          }
        ],
        build: false,
        deploy: false,
        config_provider: DefaultConfigProvider,
        continue_on_plugin_errors: true
      ]

      capture_log(fn ->
        assert {:ok, result} = Orchestrator.execute_workflow(workflow_config)
        
        # Should complete despite plugin failure
        assert result.download_completed == true
        # Should have applied some plugins but not all
        assert result.plugins_applied >= 0
        assert Map.has_key?(result, :plugin_errors)
        assert length(result.plugin_errors) > 0
      end)
    end
  end

  describe "Orchestrator configuration integration" do
    @tag :config_provider_integration
    test "orchestrator uses config provider for all decisions", %{temp_dir: temp_dir} do
      # Create a custom config provider for testing
      defmodule TestConfigProvider do
        @behaviour Defdo.TailwindBuilder.ConfigProvider
        
        def get_known_checksums do
          DefaultConfigProvider.get_known_checksums()
        end
        
        def get_build_policies do
          %{
            "3.4.17" => :allowed,
            "4.1.11" => :deprecated
          }
        end
        
        def get_deployment_policies do
          %{
            "3.4.17" => :allowed,
            "4.1.11" => :blocked
          }
        end
        
        def validate_operation_policy(version, operation) do
          policies = case operation do
            :build -> get_build_policies()
            :deploy -> get_deployment_policies()
            _ -> %{}
          end
          
          case Map.get(policies, version, :allowed) do
            :allowed -> :ok
            :deprecated -> :deprecated
            :blocked -> {:error, :operation_blocked}
          end
        end
      end

      workflow_config = [
        version: "3.4.17",
        source_path: temp_dir,
        plugins: [],
        build: false,
        deploy: false,
        config_provider: TestConfigProvider
      ]

      assert {:ok, result} = Orchestrator.execute_workflow(workflow_config)
      assert result.config_provider == TestConfigProvider

      # Test with blocked version
      blocked_workflow = Keyword.put(workflow_config, :version, "4.1.11")
      blocked_workflow = Keyword.put(blocked_workflow, :deploy, true)

      # Should respect config provider policy
      assert {:error, {step, _error}} = Orchestrator.execute_workflow(blocked_workflow)
      assert step in [:validate_download_policy, :validate_deploy_policy, :deploy]
    end

    @tag :environment_specific_config
    test "orchestrator adapts to different environments", %{temp_dir: temp_dir} do
      # Test development environment
      dev_config = [
        version: "3.4.17",
        source_path: temp_dir,
        plugins: [
          %{
            "version" => ~s["daisyui": "^4.12.23"],
            "statement" => ~s['daisyui': require('daisyui')]
          }
        ],
        build: false,
        deploy: false,
        config_provider: DefaultConfigProvider,
        environment: :development,
        debug: true
      ]

      capture_log(fn ->
        assert {:ok, dev_result} = Orchestrator.execute_workflow(dev_config)
        assert dev_result.environment == :development
        assert Map.has_key?(dev_result, :debug_info)
      end)

      # Test production environment (more strict)
      prod_config = Keyword.merge(dev_config, [
        environment: :production,
        debug: false,
        validate_checksums: true,
        strict_mode: true
      ])

      capture_log(fn ->
        assert {:ok, prod_result} = Orchestrator.execute_workflow(prod_config)
        assert prod_result.environment == :production
        refute Map.has_key?(prod_result, :debug_info)
      end)
    end
  end

  describe "Orchestrator performance and scalability" do
    @tag :concurrent_workflows
    @tag timeout: 60_000
    test "orchestrator handles concurrent workflows safely", %{temp_dir: temp_dir} do
      # Create multiple concurrent workflows
      workflows = for i <- 1..3 do
        workflow_dir = Path.join(temp_dir, "workflow_#{i}")
        File.mkdir_p!(workflow_dir)
        
        Task.async(fn ->
          workflow_config = [
            version: "3.4.17",
            source_path: workflow_dir,
            plugins: [
              %{
                "version" => ~s["daisyui": "^4.12.23"],
                "statement" => ~s['daisyui': require('daisyui')]
              }
            ],
            build: false,
            deploy: false,
            config_provider: DefaultConfigProvider,
            workflow_id: "concurrent_#{i}"
          ]
          
          Orchestrator.execute_workflow(workflow_config)
        end)
      end

      # All workflows should complete successfully
      results = Task.await_many(workflows, 45_000)
      
      for {result, index} <- Enum.with_index(results, 1) do
        assert {:ok, workflow_result} = result
        assert workflow_result.download_completed == true
        
        # Verify each workflow created its own files
        workflow_dir = Path.join(temp_dir, "workflow_#{index}")
        extracted_path = Path.join([workflow_dir, "tailwindcss-3.4.17"])
        assert File.exists?(extracted_path)
      end
    end

    @tag :workflow_metrics
    test "orchestrator provides detailed metrics and timing", %{temp_dir: temp_dir} do
      workflow_config = [
        version: "3.4.17",
        source_path: temp_dir,
        plugins: [
          %{
            "version" => ~s["daisyui": "^4.12.23"],
            "statement" => ~s['daisyui': require('daisyui')]
          }
        ],
        build: false,
        deploy: false,
        config_provider: DefaultConfigProvider,
        collect_metrics: true
      ]

      capture_log(fn ->
        assert {:ok, result} = Orchestrator.execute_workflow(workflow_config)
        
        # Should include detailed metrics
        assert Map.has_key?(result, :metrics)
        metrics = result.metrics
        
        assert Map.has_key?(metrics, :download_time)
        assert Map.has_key?(metrics, :plugin_time)
        assert Map.has_key?(metrics, :total_time)
        
        # Timing values should be reasonable
        assert metrics.download_time > 0
        assert metrics.total_time >= metrics.download_time
        
        if metrics.plugin_time > 0 do
          assert metrics.total_time >= metrics.download_time + metrics.plugin_time
        end
      end)
    end
  end

  describe "Orchestrator integration with external systems" do
    @tag :filesystem_integration
    test "orchestrator handles filesystem edge cases", %{temp_dir: temp_dir} do
      # Test with read-only directory (simulate CI environment)
      readonly_dir = Path.join(temp_dir, "readonly")
      File.mkdir_p!(readonly_dir)
      
      # Don't actually make it read-only as it would break cleanup
      # Instead test with path that requires creation
      
      nested_path = Path.join([temp_dir, "deep", "nested", "path"])
      
      workflow_config = [
        version: "3.4.17",
        source_path: nested_path,
        plugins: [],
        build: false,
        deploy: false,
        config_provider: DefaultConfigProvider,
        create_directories: true
      ]

      assert {:ok, result} = Orchestrator.execute_workflow(workflow_config)
      
      # Should have created the nested directory structure
      assert File.exists?(nested_path)
      assert File.dir?(nested_path)
      assert result.download_completed == true
    end

    @tag :network_resilience
    test "orchestrator handles network issues gracefully", %{temp_dir: temp_dir} do
      # Test with invalid URL (simulate network issues)
      workflow_config = [
        version: "999.999.999",  # This will cause download to fail
        source_path: temp_dir,
        plugins: [],
        build: false,
        deploy: false,
        config_provider: DefaultConfigProvider,
        retry_on_network_error: true,
        max_retries: 2
      ]

      # Should fail gracefully with network error
      assert {:error, {step, _error}} = Orchestrator.execute_workflow(workflow_config)
      assert step == :download
    end
  end

  describe "End-to-end real world scenarios" do
    @tag :developer_workflow
    @tag timeout: 60_000
    test "complete developer customization workflow", %{temp_dir: temp_dir} do
      # Simulate complete developer workflow
      workflow_steps = [
        # Step 1: Initial setup
        [
          version: "3.4.17",
          source_path: temp_dir,
          plugins: [],
          build: false,
          deploy: false,
          config_provider: DefaultConfigProvider,
          step_name: "initial_download"
        ],
        
        # Step 2: Add plugins
        [
          version: "3.4.17",
          source_path: temp_dir,
          plugins: [
            %{
              "version" => ~s["daisyui": "^4.12.23"],
              "statement" => ~s['daisyui': require('daisyui')]
            }
          ],
          build: false,
          deploy: false,
          config_provider: DefaultConfigProvider,
          step_name: "add_plugins",
          skip_download: true  # Already downloaded
        ]
      ]

      workflow_results = for workflow_config <- workflow_steps do
        {result, _logs} = ExUnit.CaptureLog.with_log(fn ->
          case Orchestrator.execute_workflow(workflow_config) do
            {:ok, result} ->
              assert result.download_completed == true or workflow_config[:skip_download]
              result
              
            {:error, reason} ->
              flunk("Workflow step #{workflow_config[:step_name]} failed: #{inspect(reason)}")
          end
        end)
        
        result
      end

      # Verify cumulative results
      assert length(workflow_results) == 2
      
      [first_result, second_result] = workflow_results
      
      # First step should have no plugins applied (only download)
      assert first_result.plugins_applied == 0
      
      # Second step should have plugins applied
      assert second_result.plugins_applied > 0
      
      # Verify final state
      extracted_path = Path.join([temp_dir, "tailwindcss-3.4.17"])
      assert File.exists?(extracted_path)
    end

    @tag :ci_cd_workflow
    @tag timeout: 60_000
    test "automated CI/CD pipeline workflow", %{temp_dir: temp_dir} do
      # Simulate CI/CD pipeline
      ci_workflow = [
        version: "3.4.17",
        source_path: temp_dir,
        plugins: [
          %{
            "version" => ~s["daisyui": "^4.12.23"],
            "statement" => ~s['daisyui': require('daisyui')]
          }
        ],
        build: false,  # Would be true in real CI
        deploy: false, # Would be true in real CI
        config_provider: DefaultConfigProvider,
        environment: :ci,
        validate_checksums: true,
        strict_mode: true,
        generate_reports: true
      ]

      capture_log(fn ->
        assert {:ok, result} = Orchestrator.execute_workflow(ci_workflow)
        
        # CI-specific validations
        assert result.environment == :ci
        assert result.download_completed == true
        assert result.plugins_applied > 0
        
        # Should generate CI reports
        if Map.has_key?(result, :reports) do
          assert Map.has_key?(result.reports, :validation_report)
          assert Map.has_key?(result.reports, :plugin_report)
        end
        
        # Verify strict mode compliance
        assert Map.has_key?(result, :compliance_checks)
      end)
    end

    @tag :multi_version_workflow
    test "workflow handles multiple versions correctly", %{temp_dir: temp_dir} do
      versions_to_test = ["3.4.17", "4.1.11"]
      
      for version <- versions_to_test do
        version_dir = Path.join(temp_dir, "v#{version}")
        File.mkdir_p!(version_dir)
        
        workflow_config = [
          version: version,
          source_path: version_dir,
          plugins: [
            %{
              "version" => ~s["daisyui": "^4.12.23"],
              "statement" => ~s['daisyui': require('daisyui')]
            }
          ],
          build: false,
          deploy: false,
          config_provider: DefaultConfigProvider
        ]

        case DefaultConfigProvider.get_known_checksums()[version] do
          nil ->
            # Skip versions without known checksums
            :ok
            
          _checksum ->
            capture_log(fn ->
              assert {:ok, result} = Orchestrator.execute_workflow(workflow_config)
              assert result.version == version
              assert result.download_completed == true
              
              # Verify version-specific structure
              extracted_path = Path.join([version_dir, "tailwindcss-#{version}"])
              assert File.exists?(extracted_path)
            end)
        end
      end
    end
  end
end