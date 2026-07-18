# Toolchain image for building Tailwind CLI standalone binaries.
#
# Provides Elixir/OTP, Node, pnpm, Rust, Bun, and build-essential.
# Does NOT copy project source — mount the repo at /workspace at runtime.
#
# Pinned tool versions match .tool-versions in the project root.
# Build args allow version overrides without editing this file.

# elixir >= 1.19 required by the worker that builds FROM this base image.
# -slim (Debian slim, glibc) instead of the full image: ~2GB smaller, still
# glibc so the native oxide build produces glibc (gnu) binaries — NOT musl, which
# an Alpine base would force and would mismatch our linux-x64/arm64 (gnu) targets.
FROM elixir:1.19-slim

# Versions track what recent Tailwind releases require. Tailwind 4.3.x bumped
# its whole toolchain vs 4.2.x: node >=22.13 (pnpm 11 needs it), pnpm 11.9.0
# (packageManager field; applies the lightningcss pnpm-patch that lets the bun
# standalone embed lightningcss's native .node), rust 1.95.0 (rust-toolchain.toml),
# bun 1.3.14. pnpm is provided via corepack so each Tailwind version's pinned
# packageManager is used automatically (9.6.0 for 4.2.2, 11.9.0 for 4.3.2).
ARG NODE_VERSION=22.20.0
ARG RUST_VERSION=1.95.0
ARG BUN_VERSION=1.3.14
ARG PNPM_VERSION=11.9.0
# WASI SDK provides clang + wasm-ld + the wasi sysroot that napi-rs needs to
# build the oxide crate's wasm32-wasip1-threads artifact. The Rust target alone
# (rustup target add) is not enough — without this the workspace build fails at
# @tailwindcss/oxide's build:wasm step ("dist directory not found" downstream).
# Tag is wasi-sdk-<MAJOR>, asset is wasi-sdk-<VERSION>-<arch>-linux.tar.gz.
ARG WASI_SDK_MAJOR=25
ARG WASI_SDK_VERSION=25.0

ENV LANG=C.UTF-8
ENV PATH="/root/.cargo/bin:/root/.bun/bin:${PATH}"
# napi-rs resolves the wasm C toolchain from WASI_SDK_PATH.
ENV WASI_SDK_PATH="/opt/wasi-sdk"

# System packages: compiler toolchain, curl, git, archive tools.
# python3: node-gyp needs it to build native npm modules from source. On arm64,
# some Tailwind dev deps (tree-sitter-*) have no prebuilt binary and compile via
# node-gyp during `pnpm install` — without python3 that fails with
# "Could not find any Python installation to use" and the whole install exits 1.
# amd64 uses prebuilts so it doesn't hit this, but python3 is harmless there.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    python3 \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Node — official binary, version-pinned, arch-detected
RUN ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/') && \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" \
    | tar -xJ -C /usr/local --strip-components=1

# pnpm — via corepack so the version follows each source's `packageManager`
# field (Tailwind 4.2.2 -> pnpm 9.6.0, 4.3.2 -> pnpm 11.9.0). corepack ships with
# Node. Activate a sane default; the source's packageManager overrides it, and
# the lightningcss pnpm-patch only applies with the version the source pins.
RUN corepack enable && corepack prepare "pnpm@${PNPM_VERSION}" --activate && npm cache clean --force

# Rust — rustup, pinned toolchain, minimal profile (no rust-docs/clippy/rustfmt)
# to keep the image lean; PATH set via ENV above.
RUN curl -fsSL https://sh.rustup.rs | \
    sh -s -- -y --profile minimal --default-toolchain "${RUST_VERSION}" --no-modify-path

# wasm32 target: the workspace build runs the oxide crate's `build:wasm`
# (napi build --target wasm32-wasip1-threads), so this target is required.
RUN rustup target add wasm32-wasip1-threads

# WASI SDK: the C/link half of the wasm build. napi-rs invokes
# $WASI_SDK_PATH/bin/clang + wasm-ld against the wasi sysroot to produce the
# oxide wasm artifact. Self-contained tarball (no apt LLVM) to keep the base
# slim. Arch-detected like the Node/Bun steps (x86_64 / arm64).
RUN ARCH=$(uname -m | sed 's/x86_64/x86_64/;s/aarch64/arm64/') && \
    curl -fsSL \
    "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_MAJOR}/wasi-sdk-${WASI_SDK_VERSION}-${ARCH}-linux.tar.gz" \
    -o /tmp/wasi-sdk.tar.gz && \
    mkdir -p /opt/wasi-sdk && \
    tar -xzf /tmp/wasi-sdk.tar.gz -C /opt/wasi-sdk --strip-components=1 && \
    rm -f /tmp/wasi-sdk.tar.gz && \
    "${WASI_SDK_PATH}/bin/clang" --version

# Bun — GitHub release, version-pinned, arch-detected
RUN ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/aarch64/') && \
    mkdir -p /root/.bun/bin && \
    curl -fsSL \
    "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${ARCH}.zip" \
    -o /tmp/bun.zip && \
    unzip -q /tmp/bun.zip -d /tmp/bun-extract && \
    mv "/tmp/bun-extract/bun-linux-${ARCH}/bun" /root/.bun/bin/bun && \
    chmod +x /root/.bun/bin/bun && \
    rm -rf /tmp/bun.zip /tmp/bun-extract

# Hex + Rebar — Mix package manager bootstrapping, baked into the image
RUN mix local.hex --force && mix local.rebar --force

# Verify all tools are reachable — build fails fast if any are missing
RUN elixir --version && \
    node --version && \
    pnpm --version && \
    rustc --version && \
    cargo --version && \
    bun --version

WORKDIR /workspace
