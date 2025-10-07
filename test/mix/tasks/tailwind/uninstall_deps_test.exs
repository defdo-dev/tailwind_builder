defmodule Mix.Tasks.Tailwind.UninstallDepsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  import Mock
  alias Mix.Tasks.Tailwind.UninstallDeps

  @moduletag :capture_log

  describe "run/1" do
    test "calls Dependencies.uninstall! and shows success message" do
      with_mock Defdo.TailwindBuilder.Dependencies, [:passthrough], uninstall!: fn -> :ok end do
        output =
          capture_io(fn ->
            UninstallDeps.run([])
          end)

        assert output =~ "Uninstalling Tailwind CLI build dependencies..."
        assert output =~ "✓ Dependencies uninstalled successfully"
        assert called(Defdo.TailwindBuilder.Dependencies.uninstall!())
      end
    end

    test "handles when Dependencies.uninstall! raises exception" do
      error_message = "Failed to uninstall nodejs"

      with_mock Defdo.TailwindBuilder.Dependencies, [:passthrough],
        uninstall!: fn -> raise RuntimeError, error_message end do
        assert_raise RuntimeError, error_message, fn ->
          capture_io(fn ->
            UninstallDeps.run([])
          end)
        end

        assert called(Defdo.TailwindBuilder.Dependencies.uninstall!())
      end
    end

    test "ignores command line arguments" do
      with_mock Defdo.TailwindBuilder.Dependencies, [:passthrough], uninstall!: fn -> :ok end do
        output =
          capture_io(fn ->
            # Should work the same regardless of arguments
            UninstallDeps.run(["--force", "--dry-run"])
          end)

        assert output =~ "Uninstalling Tailwind CLI build dependencies..."
        assert output =~ "✓ Dependencies uninstalled successfully"
        assert called(Defdo.TailwindBuilder.Dependencies.uninstall!())
      end
    end

    test "calls Mix.shell().info for output" do
      # Mock Mix.shell and Dependencies to verify behavior
      with_mocks([
        {Defdo.TailwindBuilder.Dependencies, [:passthrough], [uninstall!: fn -> :ok end]},
        {Mix.Shell.IO, [:passthrough], [info: fn _message -> :ok end]}
      ]) do
        # Set the shell to our mocked one
        Mix.shell(Mix.Shell.IO)

        UninstallDeps.run([])

        # Verify Mix.Shell.IO.info was called with correct messages
        assert called(Mix.Shell.IO.info("Uninstalling Tailwind CLI build dependencies..."))
        assert called(Mix.Shell.IO.info("✓ Dependencies uninstalled successfully"))
        assert called(Defdo.TailwindBuilder.Dependencies.uninstall!())
      end
    end
  end

  describe "task metadata" do
    test "has correct @shortdoc" do
      # Verify the task has proper documentation
      assert UninstallDeps.__info__(:attributes)[:shortdoc] == [
               "Uninstalls Tailwind CLI build dependencies"
             ]
    end

    test "uses Mix.Task behavior" do
      # Verify it implements the Mix.Task behavior
      assert Mix.Task in UninstallDeps.__info__(:attributes)[:behaviour] || []
    end
  end
end
