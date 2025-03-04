# Tailwind CLI Builder

A tool for building custom Tailwind CSS CLI binaries with integrated plugins like DaisyUI.

## Features

- Download Tailwind CSS source code (supports v3.x and v4.x)
- Patch source files to include plugins (currently supports DaisyUI)
- Build standalone CLI binaries for multiple platforms
- Deploy built binaries to R2 storage

## Requirements

- Elixir 1.14+
- Node.js and npm/pnpm
- Rust
- Git

## Basic Usage
```elixir
# Version 3.x
alias Defdo.TailwindBuilder

# Download Tailwind source
{:ok, _} = TailwindBuilder.download("/path/to/working/dir", "3.4.17")

# Add DaisyUI plugin
TailwindBuilder.add_plugin("daisyui", "3.4.17", "/path/to/working/dir")

# Build the CLI
{:ok, result} = TailwindBuilder.build("3.4.17", "/path/to/working/dir")

# Deploy to R2 (optional)
TailwindBuilder.deploy_r2("3.4.17", "/path/to/working/dir", "your-bucket-name")
```

```elixir
# Version 4.x
alias Defdo.TailwindBuilder
# For Tailwind v4 with DaisyUI v5
daisyui_v5 = %{
  "version" => ~s["daisyui": "^5.0.0"]
}

{:ok, _} = TailwindBuilder.download("/path/to/working/dir", "4.0.9")
TailwindBuilder.add_plugin(daisyui_v5, "4.0.9", "/path/to/working/dir")
{:ok, result} = TailwindBuilder.build("4.0.9", "/path/to/working/dir")
```

```elixir
custom_plugin = %{
  "version" => ~s["my-plugin": "^1.0.0"],
  "statement" => ~s['my-plugin': require('my-plugin')]
}

TailwindBuilder.add_plugin(custom_plugin, "3.4.17", "/path/to/working/dir")
```

> Uploading to r2 requires the following environment variables to be set:

```elixir
config :ex_aws,
  access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
  region: "auto",
  s3: [
    host: "your-account.r2.cloudflarestorage.com"
  ]
```

## Installation

Add the package to your dependencies:

```elixir
def deps do
  [
    {:tailwind_cli_builder, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/tailwind_builder>.

## Contribution
Feel free to submit issues and pull requests.

```bash
git clone https://github.com/defdo-dev/tailwind_builder.git
cd tailwind_builder
mix deps.get
```
Run tests:
`mix test`