# TailwindBuilder

A comprehensive, modular system for downloading, building, and deploying TailwindCSS with advanced telemetry and monitoring capabilities.

## 🚀 Key Features

- **Modular Architecture**: Clean separation of concerns with dedicated modules
- **Multi-Environment Support**: Different configurations for dev/test/prod/staging  
- **Advanced Telemetry**: Real-time monitoring, metrics, and dashboards
- **Plugin Support**: Easy integration of TailwindCSS plugins (DaisyUI, Typography, etc.)
- **Multiple Deployment Targets**: S3, R2, CDN, and local deployment
- **Comprehensive Testing**: 267+ tests ensuring reliability
- **Zero Warnings**: Production-ready code quality

## 📋 Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start) 
- [Architecture](#architecture)
- [Telemetry & Monitoring](#telemetry--monitoring)
- [API Reference](#api-reference)
- [Configuration](#configuration)
- [Testing](#testing)
- [LiveBook](#livebook)

## 🔧 Installation

Add `tailwind_builder` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tailwind_builder, "~> 1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

### System Requirements

- Elixir 1.14+
- Node.js and npm/pnpm
- Rust
- Git

The build dependencies can be managed via mix tasks:

```bash
mix tailwind.install_deps   # Installs Tailwind CLI build dependencies
mix tailwind.uninstall_deps # Uninstalls Tailwind CLI build dependencies
```

## 🚀 Quick Start
### New Modular API (Recommended)

```elixir
# Start the application
{:ok, _} = Application.ensure_all_started(:tailwind_builder)

# Build and deploy with modern modular architecture
{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui", "@tailwindcss/typography"],
  target: :local,
  output_dir: "./dist"
])
```

### With Custom Configuration

```elixir
# Use environment-specific config provider
config_provider = Defdo.TailwindBuilder.ConfigProviders.ProductionConfigProvider

{:ok, result} = Defdo.TailwindBuilder.build_and_deploy([
  version: "4.1.11",
  plugins: ["daisyui"],
  target: :r2,
  config_provider: config_provider
])
```

### Legacy API (Still Supported)

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

## 🏗️ Architecture

The system is built with a modular architecture:

```
TailwindBuilder/
├── Core                 # Main orchestration logic
├── Downloader          # Version download and extraction
├── Builder             # Plugin application and compilation
├── Deployer            # Multi-target deployment
├── Orchestrator        # Workflow management
├── ConfigProviders/    # Environment-specific configurations
│   ├── Development     # Fast, permissive for dev
│   ├── Production      # Strict, secure for prod
│   ├── Staging         # Balanced for staging
│   └── Testing         # Fast, mock-friendly for tests
├── Telemetry           # Real-time monitoring
├── Metrics             # Specialized metrics collection
└── Dashboard           # Monitoring dashboard
```

### Key Modules

- **Core**: Main entry point and orchestration logic
- **Downloader**: Handles TailwindCSS version downloads with checksum validation
- **Builder**: Applies plugins and compiles assets  
- **Deployer**: Supports multiple deployment targets (S3, R2, CDN, local)
- **Telemetry**: Real-time span tracking and structured logging
- **Dashboard**: Live monitoring with multiple output formats

## 📊 Telemetry & Monitoring

### Starting Telemetry

```elixir
# Start with default configuration
{:ok, _} = Defdo.TailwindBuilder.Telemetry.start_link([])

# Check if enabled
Defdo.TailwindBuilder.Telemetry.enabled?() # true/false
```

### Real-time Dashboard

```elixir
# Live terminal dashboard (auto-refreshing)
Defdo.TailwindBuilder.Dashboard.display_live_dashboard(10) # 10 second refresh

# Generate dashboard in different formats
dashboard_text = Defdo.TailwindBuilder.Dashboard.generate_summary(format: :text)
dashboard_json = Defdo.TailwindBuilder.Dashboard.generate_summary(format: :json) 
dashboard_html = Defdo.TailwindBuilder.Dashboard.generate_summary(format: :html)

# Export dashboard data
Defdo.TailwindBuilder.Dashboard.export_dashboard("/tmp/dashboard.json", :json)
```

### Automatic Operation Tracking

```elixir
# Operations are automatically tracked with telemetry
result = Defdo.TailwindBuilder.Telemetry.track_download("4.1.11", fn ->
  # Your download logic here
  {:ok, "Download completed"}
end)

# View active operations
active_spans = Defdo.TailwindBuilder.Telemetry.get_active_spans()
```

## 📚 API Reference

### Core Module

```elixir
# Main build and deploy function (recommended)
Defdo.TailwindBuilder.build_and_deploy(opts)

# Options:
# - version: TailwindCSS version (required)
# - plugins: List of plugin names
# - target: Deployment target (:local, :s3, :r2, :cdn)
# - output_dir: Local output directory
# - config_provider: Custom config provider module
```

### Individual Module Usage

```elixir
# Download specific version
Defdo.TailwindBuilder.Downloader.download_and_extract([
  version: "4.1.11",
  output_dir: "/tmp/tailwind",
  checksum_validation: true
])

# Apply plugins
Defdo.TailwindBuilder.Builder.apply_plugins([
  source_dir: "/tmp/tailwind/4.1.11",
  plugins: ["daisyui", "@tailwindcss/typography"],
  output_dir: "/tmp/build"
])

# Deploy to target
Defdo.TailwindBuilder.Deployer.deploy([
  source_dir: "/tmp/build",
  target: :s3,
  bucket: "my-assets"
])
```

## ⚙️ Configuration

### Environment-Specific Providers

```elixir
# Development (permissive, fast)
config_provider = Defdo.TailwindBuilder.ConfigProviders.DevelopmentConfigProvider

# Production (strict, secure)
config_provider = Defdo.TailwindBuilder.ConfigProviders.ProductionConfigProvider

# Automatic selection based on Mix.env()
provider = Defdo.TailwindBuilder.ConfigProviderFactory.get_provider()
```

### Deployment Configuration

For R2/S3 deployment, set these environment variables:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export CLOUDFLARE_ACCOUNT_ID="your-account-id"  # For R2
```

## 🧪 Testing

Run the complete test suite:

```bash
# All tests (267 tests)
mix test

# Specific test categories
mix test --only download
mix test --only build
mix test --only deploy
mix test --only telemetry
mix test --only dashboard

# With coverage
mix test --cover

# Clean compilation (no warnings)
mix test --warnings-as-errors
```

## 📓 LiveBook

Explore the system interactively with the included LiveBook:

```bash
# Start LiveBook
livebook server

# Open the included notebook
# Navigate to: livebooks/tailwind_v4.livemd
```

The LiveBook provides:
- Interactive exploration of all modules
- Real-time telemetry demonstration
- Step-by-step build process walkthrough
- Dashboard visualization examples

## 🔍 Troubleshooting

### Common Issues

**Downloads Failing**
```elixir
# Check network connectivity and version availability
Defdo.TailwindBuilder.Downloader.validate_version("4.1.11")
```

**Telemetry Not Working**
```elixir
# Check telemetry status
stats = Defdo.TailwindBuilder.Telemetry.get_stats()
IO.inspect(stats)
```

**Debug Mode**
```elixir
Logger.configure(level: :debug)
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch  
3. Add tests for new functionality
4. Ensure all tests pass: `mix test`
5. Ensure no warnings: `mix compile --warnings-as-errors`
6. Submit a pull request

### Development Setup

```bash
git clone <repository>
cd tailwind_builder
mix deps.get
mix test
```

## 📄 License

MIT License - see LICENSE.md file for details.

---

*Built with ❤️ and Elixir - A modern, modular approach to TailwindCSS building*