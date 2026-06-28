SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

MIX ?= mix
MIX_ENV ?= dev
CORE_DIR := $(abspath .)
HUB_DIR := $(abspath ../tailwind_builder_hub)
WORKER_DIR := $(abspath ../tailwind_builder_worker)

IMAGE_NAME  ?= hub.defdo.ninja/defdo/tailwind-builder
IMAGE_TAG   ?= 0.1.0
DOCKERFILE  ?= docker/tailwind-builder-v4/Dockerfile

.PHONY: help setup compile test server hub worker \
        image-build image-verify docker-canary docker-shell

help:
	@printf '%s\n' \
		'Usage:' \
		'  make setup' \
		'  make compile' \
		'  make test' \
		'  make server' \
		'  make hub CMD=phx.server' \
		'  make worker CMD=run ARGS=--no-halt' \
		'' \
		'Docker toolchain image:' \
		'  make image-build        Build $(IMAGE_NAME):$(IMAGE_TAG)' \
		'  make image-verify       Verify tool versions inside image' \
		'  make docker-canary      Run canary release inside container (needs R2 env vars)' \
		'  make docker-shell       Drop into a shell in the container'

setup:
	set -euo pipefail
	cd "$(CORE_DIR)" && MIX_ENV=dev $(MIX) deps.get
	cd "$(HUB_DIR)" && MIX_ENV=dev $(MIX) deps.get
	cd "$(WORKER_DIR)" && MIX_ENV=dev $(MIX) deps.get

compile:
	set -euo pipefail
	cd "$(CORE_DIR)" && MIX_ENV=dev $(MIX) compile
	cd "$(HUB_DIR)" && MIX_ENV=dev $(MIX) compile
	cd "$(WORKER_DIR)" && MIX_ENV=dev $(MIX) compile

test:
	set -euo pipefail
	cd "$(CORE_DIR)" && MIX_ENV=test $(MIX) deps.get && MIX_ENV=test $(MIX) test
	cd "$(HUB_DIR)" && MIX_ENV=test $(MIX) deps.get && MIX_ENV=test $(MIX) test
	cd "$(WORKER_DIR)" && MIX_ENV=test $(MIX) deps.get && MIX_ENV=test $(MIX) test

server:
	set -euo pipefail
	cd "$(HUB_DIR)" && MIX_ENV=dev $(MIX) phx.server &
	hub_pid=$$!
	cd "$(WORKER_DIR)" && MIX_ENV=dev $(MIX) run --no-halt &
	worker_pid=$$!
	echo "hub pid: $$hub_pid"
	echo "worker pid: $$worker_pid"
	echo "hub:    $(HUB_DIR)"
	echo "worker: $(WORKER_DIR)"
	trap 'kill $$hub_pid $$worker_pid 2>/dev/null || true' EXIT INT TERM
	while true; do
		if ! kill -0 $$hub_pid 2>/dev/null; then
			wait $$hub_pid || true
			exit 1
		fi
		if ! kill -0 $$worker_pid 2>/dev/null; then
			wait $$worker_pid || true
			exit 1
		fi
		sleep 1
	done

hub:
	@if [ -z "$(CMD)" ]; then \
		echo "Usage: make hub CMD=phx.server [ARGS=...]" >&2; \
		exit 1; \
	fi
	set -euo pipefail
	cd "$(HUB_DIR)" && MIX_ENV="$(MIX_ENV)" $(MIX) $(CMD) $(ARGS)

worker:
	@if [ -z "$(CMD)" ]; then \
		echo "Usage: make worker CMD=run [ARGS=...]" >&2; \
		exit 1; \
	fi
	set -euo pipefail
	cd "$(WORKER_DIR)" && MIX_ENV="$(MIX_ENV)" $(MIX) $(CMD) $(ARGS)

image-build:
	docker build \
		-f "$(DOCKERFILE)" \
		-t "$(IMAGE_NAME):$(IMAGE_TAG)" \
		.

image-verify:
	@echo "--- tool versions inside $(IMAGE_NAME):$(IMAGE_TAG) ---"
	docker run --rm "$(IMAGE_NAME):$(IMAGE_TAG)" sh -c \
		'elixir --version && node --version && pnpm --version && rustc --version && bun --version'

# Pass R2 credentials by name — values come from the shell environment, never printed.
# Set R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_HOST, R2_REGION before running.
docker-canary:
	docker run --rm \
		-w /workspace \
		-v "$(CORE_DIR)":/workspace \
		-e R2_ACCESS_KEY_ID \
		-e R2_SECRET_ACCESS_KEY \
		-e R2_HOST \
		-e R2_REGION \
		"$(IMAGE_NAME):$(IMAGE_TAG)" \
		sh -c 'mix deps.get && mix tailwind.release \
			--version 4.2.2 \
			--channel v4.2.2-rc1-linux-canary \
			--config-provider testing \
			--bucket defdo \
			--prefix tailwind_cli_daisyui_ci_canary \
			--storage-base-url https://storage.defdo.de \
			--plugin daisyui_v5 \
			--smoke-test \
			--verify-upload \
			--verify-smoke-test \
			--overwrite-policy fail'

docker-shell:
	docker run --rm -it \
		-w /workspace \
		-v "$(CORE_DIR)":/workspace \
		"$(IMAGE_NAME):$(IMAGE_TAG)" \
		bash
