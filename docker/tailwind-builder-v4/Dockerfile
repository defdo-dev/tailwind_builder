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

ARG NODE_VERSION=22.6.0
ARG RUST_VERSION=1.90.0
ARG BUN_VERSION=1.2.23
ARG PNPM_VERSION=9.15.9

ENV LANG=C.UTF-8
ENV PATH="/root/.cargo/bin:/root/.bun/bin:${PATH}"

# System packages: compiler toolchain, curl, git, archive tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Node — official binary, version-pinned, arch-detected
RUN ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/') && \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" \
    | tar -xJ -C /usr/local --strip-components=1

# pnpm — installed via npm with pinned version
RUN npm install -g "pnpm@${PNPM_VERSION}"

# Rust — rustup, pinned toolchain, minimal profile (no rust-docs/clippy/rustfmt)
# to keep the image lean; PATH set via ENV above.
RUN curl -fsSL https://sh.rustup.rs | \
    sh -s -- -y --profile minimal --default-toolchain "${RUST_VERSION}" --no-modify-path

# wasm32 target: the workspace build runs the oxide crate's `build:wasm`
# (napi build --target wasm32-wasip1-threads), so this target is required.
RUN rustup target add wasm32-wasip1-threads

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
