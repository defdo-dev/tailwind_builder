defmodule Mix.Tasks.Tailwind.InstallDepsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  import Mock
  alias Mix.Tasks.Tailwind.InstallDeps

  @moduletag :capture_log

  describe "run/1" do
    test "calls Dependencies.install! and shows success message" do
      with_mock Defdo.TailwindBuilder.Dependencies, [:passthrough], install!: fn -> :ok end do
        output =
          capture_io(fn ->
            InstallDeps.run([])
          end)

        assert output =~ "Installing Tailwind CLI build dependencies..."
        assert output =~ "✓ Dependencies installed successfully"
        assert called(Defdo.TailwindBuilder.Dependencies.install!())
      end
    end

    test "handles when Dependencies.install! raises exception" do
      error_message = "Failed to install rust"

      with_mock Defdo.TailwindBuilder.Dependencies, [:passthrough],
        install!: fn -> raise RuntimeError, error_message end do
        assert_raise RuntimeError, error_message, fn ->
          capture_io(fn ->
            InstallDeps.run([])
          end)
        end

        assert called(Defdo.TailwindBuilder.Dependencies.install!())
      end
    end

    test "ignores command line arguments" do
      with_mock Defdo.TailwindBuilder.Dependencies, [:passthrough], install!: fn -> :ok end do
        output =
          capture_io(fn ->
            # Should work the same regardless of arguments
            InstallDeps.run(["--some-flag", "value"])
          end)

        assert output =~ "Installing Tailwind CLI build dependencies..."
        assert output =~ "✓ Dependencies installed successfully"
        assert called(Defdo.TailwindBuilder.Dependencies.install!())
      end
    end

    test "calls Mix.shell().info for output" do
      # Mock Mix.shell and Dependencies to verify behavior
      with_mocks([
        {Defdo.TailwindBuilder.Dependencies, [:passthrough], [install!: fn -> :ok end]},
        {Mix.Shell.IO, [:passthrough], [info: fn _message -> :ok end]}
      ]) do
        # Set the shell to our mocked one
        Mix.shell(Mix.Shell.IO)

        InstallDeps.run([])

        # Verify Mix.Shell.IO.info was called with correct messages
        assert called(Mix.Shell.IO.info("Installing Tailwind CLI build dependencies..."))
        assert called(Mix.Shell.IO.info("✓ Dependencies installed successfully"))
        assert called(Defdo.TailwindBuilder.Dependencies.install!())
      end
    end
  end

  describe "task metadata" do
    test "has correct @shortdoc" do
      # Verify the task has proper documentation
      assert InstallDeps.__info__(:attributes)[:shortdoc] == [
               "Installs Tailwind CLI build dependencies"
             ]
    end

    test "uses Mix.Task behavior" do
      # Verify it implements the Mix.Task behavior
      assert Mix.Task in InstallDeps.__info__(:attributes)[:behaviour] || []
    end
  end
end
