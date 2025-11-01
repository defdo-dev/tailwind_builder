# TailwindBuilder Setup Guide

Complete setup instructions for TailwindCSS CLI Builder on different platforms.

## Overview

Setting up TailwindBuilder requires **TWO separate steps**:

1. **OS-level prerequisites** - Install system dependencies (before Elixir/Mix is available)
2. **Builder dependencies** - Install build tools via `mix tailwind.install_deps`

---

## Step 1: OS-Level Prerequisites

### macOS (Intel or Apple Silicon)

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install asdf version manager
brew install asdf

# Add asdf to your shell (choose your shell)
echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc   # zsh
echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.bashrc  # bash

# Reload shell
exec $SHELL

# Install Elixir
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang latest
asdf install elixir latest
asdf set --home erlang latest
asdf set --home elixir latest
```

**macOS has no additional system dependencies** - Rust cross-compilation works out of the box with Homebrew's toolchain.

### Linux (Ubuntu/Debian/Raspberry Pi OS)

**IMPORTANT**: Before installing any build tools, ensure you have system dependencies:

```bash
# Update package lists
sudo apt-get update

# Install REQUIRED system packages (needed for Bun, Rust, and cross-compilation)
sudo apt-get install -y \
  unzip \
  curl \
  build-essential \
  git \
  musl-tools \
  musl-dev
```

**Required packages:**
- `unzip` - Required by Bun installer
- `curl` - Required for downloading tools
- `build-essential` - Required for compiling native extensions
- `git` - Required for version control
- `musl-tools` + `musl-dev` - Optional, only for musl variant cross-compilation

#### Option 1: Using asdf (Traditional)

```bash
# Install asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.18.0

# Add asdf to your shell (choose your shell)
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc

# Reload shell
exec $SHELL

# Install Elixir
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang latest
asdf install elixir latest
asdf global erlang latest
asdf global elixir latest
```

#### Option 2: Using mise (Modern Alternative - Recommended)

```bash
# Install mise
curl https://mise.run | sh

# Add mise to your shell (choose your shell)
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc   # bash
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc    # zsh

# Reload shell
exec $SHELL

# Install Elixir
mise use -g erlang
mise use -g elixir

# Reload shell configuration to pick up PATH changes
source ~/.bashrc  # or source ~/.zshrc for zsh
```

**Note**: mise's `use -g` command automatically installs and sets the global version. No need to run `mise install` separately.

**Note on musl-tools**: The `musl-tools` and `musl-dev` packages are **only required** if you want to compile the musl variant (`*-musl` targets). The gnu variant (`*-gnu`) works without these packages. We install both variants to match TailwindCSS official releases.

### Linux (Fedora/RHEL/CentOS)

```bash
# Install required system packages
sudo dnf install -y \
  musl-gcc \
  musl-devel \
  gcc \
  git \
  curl \
  unzip

# Install asdf (same as Debian/Ubuntu above)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.18.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
exec $SHELL

# Install Elixir (same as above)
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang latest
asdf install elixir latest
asdf set --home erlang latest
asdf set --home elixir latest
```

### Linux (Arch)

```bash
# Install required system packages
sudo pacman -S \
  musl \
  gcc \
  git \
  curl \
  unzip

# Install asdf (same as above)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.18.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
exec $SHELL

# Install Elixir (same as above)
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang latest
asdf install elixir latest
asdf set --home erlang latest
asdf set --home elixir latest
```

### Alpine Linux

```bash
# Install required system packages
apk add \
  musl-dev \
  gcc \
  g++ \
  git \
  curl \
  bash \
  unzip

# Install asdf (same as above)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.18.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
exec $SHELL

# Install Elixir (same as above)
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang latest
asdf install elixir latest
asdf set --home erlang latest
asdf set --home elixir latest
```

---

## Step 2: Builder Dependencies

Once you have Elixir installed, navigate to the builder directory and install build dependencies:

```bash
cd builder/

# Get Elixir dependencies
mix deps.get

# Install builder dependencies (Node.js, Rust, pnpm, Bun, Rust targets)
mix tailwind.install_deps
```

This will automatically detect and use the appropriate package manager:

1. **mise** (if installed) - Modern, fast alternative to asdf
2. **asdf** (if installed) - Traditional version manager
3. **homebrew** (macOS only) - Falls back to brew on macOS
4. **Direct installation** (fallback) - Downloads and installs tools directly

**Installed tools:**
- **Node.js** - for npm/pnpm package management
- **Rust** - for TailwindCSS v4 Oxide compilation
- **Bun** - for TailwindCSS v4 standalone builds
- **pnpm** - for TailwindCSS v4 workspace management
- **Rust targets** (platform-specific):
  - `wasm32-wasip1-threads` - Required for all v4.x builds (Oxide compilation)
  - **On Linux x64**: `x86_64-unknown-linux-gnu` + `x86_64-unknown-linux-musl`
  - **On Linux ARM64**: `aarch64-unknown-linux-gnu` + `aarch64-unknown-linux-musl`
  - **On macOS**: No additional targets (native darwin targets already included)
  - **On Windows**: `x86_64-pc-windows-msvc`

**Linux Target Variants:**
- **`-gnu`**: Uses glibc (standard), dynamically linked, no extra system packages needed
- **`-musl`**: Uses musl libc (static), more portable, **requires musl-tools**

**Ubuntu/Debian Notes:**
- If `unzip` is missing, it will be auto-installed (required for Bun)
- If using mise, the `-g` flag is automatically added for global installs
- **IMPORTANT**: After installation with mise or direct install, reload your shell:
  ```bash
  source ~/.bashrc  # or source ~/.zshrc for zsh
  ```
  This is required to pick up PATH changes for Bun and Rust.

---

## Verification

### Check OS Prerequisites

```bash
# Verify asdf is installed
asdf --version

# Verify Elixir is installed
elixir --version
mix --version
```

### Check Builder Dependencies

```bash
# Verify build tools are installed
node --version
npm --version
pnpm --version
cargo --version
rustup --version
bun --version

# Verify Rust targets are installed
rustup target list --installed
```

Expected output (varies by platform):
```
# On Linux x64:
wasm32-wasip1-threads
x86_64-unknown-linux-gnu
x86_64-unknown-linux-musl

# On Linux ARM64 (Raspberry Pi):
wasm32-wasip1-threads
aarch64-unknown-linux-gnu
aarch64-unknown-linux-musl

# On macOS:
wasm32-wasip1-threads
aarch64-apple-darwin  # or x86_64-apple-darwin on Intel
```

---

## Common Issues

### Ubuntu/Linux: Bun installation fails with "unzip: command not found"

**Symptom**:
```
curl -fsSL https://bun.sh/install | bash
unzip: command not found
```

**Solution**: Install unzip before running the installer:
```bash
sudo apt-get update
sudo apt-get install -y unzip curl
```

The `mix tailwind.install_deps` task now automatically installs these dependencies on Linux.

### Ubuntu/Linux: "sudo: installer: command not found" error

**Symptom**: Direct installation fails with `installer` command not found

**Root Cause**: The `installer` command is macOS-specific and doesn't exist on Linux

**Solution**: This is now fixed in the latest version. The code detects the OS and uses appropriate installation methods:
- **Linux**: Uses `apt-get` for Node.js via NodeSource
- **macOS**: Uses `installer` for pkg files

If you encounter this, update to the latest version.

### mise: "npm install -g pnpm" fails with permission error

**Symptom**:
```
npm install -g pnpm
EACCES: permission denied
```

**Solution**: Use mise's exec command with proper flags:
```bash
mise exec -- npm install -g pnpm
```

The `mix tailwind.install_deps` task now automatically handles this correctly.

### Linux: Rust musl target installation fails

**Symptom**: `rustup target add x86_64-unknown-linux-musl` fails with linker errors

**Solution**: The `-gnu` variant will install successfully. For `-musl` support, install musl-tools:
```bash
# Ubuntu/Debian/Raspberry Pi
sudo apt-get install -y musl-tools musl-dev

# Fedora/RHEL
sudo dnf install -y musl-gcc musl-devel

# Arch
sudo pacman -S musl

# Then retry to install musl targets
rustup target add x86_64-unknown-linux-musl  # or aarch64-unknown-linux-musl
```

**Note**: You can still build TailwindCSS with only the `-gnu` variant if you don't need the musl version.

### Linux: Bun or Rust not found after installation

**Symptom**: Commands installed but not available in PATH

**Solution**: Add installation directories to your PATH:
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.bun/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

# Reload shell
exec $SHELL
```

Or use mise/asdf which handle PATH automatically:
```bash
# With mise (then reload shell)
mise use -g bun
mise use -g rust
source ~/.bashrc  # Required to pick up PATH changes

# With asdf
asdf global bun latest
asdf global rust latest
asdf reshim
```

### macOS: asdf not found after installation

**Solution**: Make sure you added asdf to your shell profile and reloaded:
```bash
echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc
exec $SHELL
```

### All platforms: Mix command not found

**Solution**: Elixir is not installed or not in PATH. Verify your version manager is working:

**With asdf:**
```bash
asdf current elixir
asdf reshim elixir
```

**With mise:**
```bash
mise current elixir
mise reshim
```

---

## Architecture Notes

### Build Node Distribution

TailwindBuilder supports distributed compilation across multiple architectures:

- **macOS (local)**: Builds native darwin-arm64 or darwin-x64 binaries
- **Linux (local)**: Builds native linux-x64 or linux-arm64 binaries
- **GitHub Actions**: Remote builds for any architecture via CI/CD

### Cross-Compilation Status

**We do NOT perform cross-compilation locally**. Each build node compiles natively for its own architecture.

- ✅ **macOS M4 → darwin-arm64**: Native compilation
- ✅ **Raspberry Pi → linux-arm64**: Native compilation
- ✅ **Linux x64 → linux-x64**: Native compilation
- ❌ **macOS M4 → linux-x64**: Use GitHub Actions or remote builder

See `DISTRIBUTED_COMPILATION_ARCHITECTURE.md` for details on remote building.

---

## Next Steps

After completing setup:

1. **Test basic build**:
   ```bash
   cd builder/
   mix test
   ```

2. **Build TailwindCSS CLI**:
   ```bash
   mix run -e 'Defdo.TailwindBuilder.build("4.1.14", "/tmp/test")'
   ```

3. **Read documentation**:
   - `CLAUDE.md` - Project overview and architecture
   - `README.md` - Usage examples
   - `DISTRIBUTED_COMPILATION_SUMMARY.md` - Remote build architecture

---

## Support

For issues or questions:
- Check existing documentation in the repository root
- Review `lib/defdo/tailwind_builder/dependencies.ex` for dependency logic
- Run `mix tailwind.install_deps` to reinstall dependencies
- Run `mix tailwind.uninstall_deps` to clean up and start fresh
