import Config

# Configure Req with reasonable defaults
config :req,
  timeout: 30_000,
  retry: [
    max_retries: 3,
    retry_delay: fn attempt -> 200 * attempt end
  ]

# Development and test environment overrides
import_config "#{config_env()}.exs"