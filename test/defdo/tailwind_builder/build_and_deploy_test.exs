defmodule Defdo.TailwindBuilder.BuildAndDeployTest do
  use ExUnit.Case, async: true

  defmodule BlockingConfigProvider do
    def validate_operation_policy(:download, _attrs), do: {:error, :blocked}
    def validate_operation_policy(_operation, _attrs), do: :ok

    def get_supported_plugins, do: %{}
    def get_operation_limits, do: %{download_timeout: 1, build_timeout: 1}
    def get_version_policy(_version), do: :test
    def get_deployment_config(_target), do: %{bucket: "test", prefix: "test"}
    def get_known_checksums, do: %{}
  end

  describe "build_and_deploy/1" do
    test "accepts public target and output_dir options transparently" do
      output_dir =
        Path.join(System.tmp_dir!(), "tailwind_builder_public_api_#{System.unique_integer([:positive])}")

      assert {:error, {:validate_policy, {:error, {:policy_violation, :blocked}}}} =
               Defdo.TailwindBuilder.build_and_deploy(
                 version: "4.1.14",
                 plugins: [],
                 target: :local,
                 output_dir: output_dir,
                 config_provider: BlockingConfigProvider
               )
    end
  end
end
