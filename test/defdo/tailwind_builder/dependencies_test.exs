defmodule Defdo.TailwindBuilder.DependenciesTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mock
  alias Defdo.TailwindBuilder.Dependencies

  @moduletag :capture_log

  describe "check!/0" do
    test "returns :ok when all required tools are installed" do
      # Mock all tools as installed
      with_mock System, [:passthrough], find_executable: fn _tool -> "/usr/bin/tool" end do
        assert :ok = Dependencies.check!()
      end
    end

    test "raises when required tools are missing" do
      # Mock some tools as missing
      with_mock System, [:passthrough],
        find_executable: fn
          # npm missing
          "npm" -> nil
          # node missing  
          "node" -> nil
          tool -> "/usr/bin/#{tool}"
        end do
        assert_raise RuntimeError, ~r/Missing required build tools: npm, node/, fn ->
          Dependencies.check!()
        end
      end
    end

    test "raises with installation instructions when tools missing" do
      with_mock System, [:passthrough], find_executable: fn _tool -> nil end do
        error =
          assert_raise RuntimeError, fn ->
            Dependencies.check!()
          end

        assert error.message =~ "Missing required build tools:"
        assert error.message =~ "You can install them manually:"
        assert error.message =~ "mix tailwind.install_deps"
      end
    end
  end

  describe "install!/0" do
    test "uses asdf when available" do
      with_mock System, [:passthrough],
        find_executable: fn
          "asdf" -> "/usr/bin/asdf"
          _tool -> nil
        end,
        cmd: fn cmd, args, opts ->
          send(self(), {:system_cmd, cmd, args, opts})
          {"output", 0}
        end do
        log =
          capture_log(fn ->
            assert :ok = Dependencies.install!()
          end)

        assert log =~ "Using asdf to install dependencies"

        # Verify asdf commands were called
        assert_received {:system_cmd, "asdf", ["plugin", "add", "nodejs"], _}
        assert_received {:system_cmd, "asdf", ["plugin", "add", "rust"], _}
        assert_received {:system_cmd, "asdf", ["install", "nodejs", "latest"], _}
        assert_received {:system_cmd, "asdf", ["install", "rust", "latest"], _}
        assert_received {:system_cmd, "asdf", ["global", "nodejs", "latest"], _}
        assert_received {:system_cmd, "asdf", ["global", "rust", "latest"], _}
        assert_received {:system_cmd, "npm", ["install", "-g", "pnpm"], _}
      end
    end

    test "uses homebrew when asdf not available but brew is" do
      with_mock System, [:passthrough],
        find_executable: fn
          "asdf" -> nil
          "brew" -> "/usr/bin/brew"
          _tool -> nil
        end,
        cmd: fn cmd, args, opts ->
          send(self(), {:system_cmd, cmd, args, opts})
          {"output", 0}
        end do
        log =
          capture_log(fn ->
            assert :ok = Dependencies.install!()
          end)

        assert log =~ "Using homebrew to install dependencies"

        assert_received {:system_cmd, "brew", ["install", "node"], _}
        assert_received {:system_cmd, "brew", ["install", "rust"], _}
        assert_received {:system_cmd, "npm", ["install", "-g", "pnpm"], _}
      end
    end

    test "uses direct installation when neither asdf nor brew available" do
      with_mock System, [:passthrough],
        find_executable: fn _tool -> nil end,
        cmd: fn cmd, args, opts ->
          send(self(), {:system_cmd, cmd, args, opts})
          {"output", 0}
        end do
        log =
          capture_log(fn ->
            assert :ok = Dependencies.install!()
          end)

        assert log =~ "Using direct installation methods"

        # Verify direct installation commands
        assert_received {:system_cmd, "curl",
                         ["--proto", "=https", "--tlsv1.2", "-sSf", "https://sh.rustup.rs"], _}

        assert_received {:system_cmd, "curl",
                         ["-o", "node.pkg", "https://nodejs.org/dist/latest/node-latest.pkg"], _}

        assert_received {:system_cmd, "sudo", ["installer", "-pkg", "node.pkg", "-target", "/"],
                         _}

        assert_received {:system_cmd, "npm", ["install", "-g", "pnpm"], _}
      end
    end
  end

  describe "uninstall!/0" do
    test "uses asdf uninstall path when asdf available" do
      with_mock System, [:passthrough],
        find_executable: fn
          "asdf" -> "/usr/bin/asdf"
          "npm" -> "/usr/bin/npm"
          _tool -> nil
        end,
        cmd: fn cmd, args, _opts ->
          case {cmd, args} do
            {"asdf", ["plugin", "list"]} -> {"nodejs\nrust\n", 0}
            _ -> {"output", 0}
          end
        end do
        log =
          capture_log(fn ->
            assert :ok = Dependencies.uninstall!()
          end)

        assert log =~ "Uninstalling via asdf"
      end
    end

    test "uses homebrew uninstall path when brew available" do
      with_mock System, [:passthrough],
        find_executable: fn
          "asdf" -> nil
          "brew" -> "/usr/bin/brew"
          "npm" -> "/usr/bin/npm"
          _tool -> nil
        end,
        cmd: fn _cmd, _args, _opts -> {"output", 0} end do
        log =
          capture_log(fn ->
            assert :ok = Dependencies.uninstall!()
          end)

        assert log =~ "Uninstalling via homebrew"
      end
    end

    test "uses manual instructions when no package manager available" do
      with_mock System, [:passthrough],
        find_executable: fn
          "npm" -> "/usr/bin/npm"
          _tool -> nil
        end,
        cmd: fn _cmd, _args, _opts -> {"output", 0} end do
        log =
          capture_log(fn ->
            assert :ok = Dependencies.uninstall!()
          end)

        assert log =~ "Manual uninstallation required"
        assert log =~ "Please remove manually:"
        assert log =~ "sudo rm -rf /usr/local/bin/node"
        assert log =~ "rustup self uninstall"
      end
    end

    test "handles npm not available gracefully" do
      with_mock System, [:passthrough],
        find_executable: fn
          "brew" -> "/usr/bin/brew"
          # npm not available
          _tool -> nil
        end,
        cmd: fn _cmd, _args, _opts -> {"output", 0} end do
        # Should not crash when npm not available
        assert :ok = Dependencies.uninstall!()
      end
    end
  end

  # Test private functions indirectly through public interface
  describe "missing_tools/0 (via check!/0)" do
    test "correctly identifies missing vs installed tools" do
      with_mock System, [:passthrough],
        find_executable: fn
          # installed
          "npm" -> "/usr/bin/npm"
          # installed  
          "node" -> "/usr/bin/node"
          # missing
          "pnpm" -> nil
          # missing
          "cargo" -> nil
        end do
        error =
          assert_raise RuntimeError, fn ->
            Dependencies.check!()
          end

        # Should only mention missing tools in the main error line
        assert error.message =~ "pnpm, cargo"
        # Should not mention installed tools in the missing tools list
        refute error.message =~ "Missing required build tools: npm"
        refute error.message =~ "Missing required build tools: node"
      end
    end
  end
end
