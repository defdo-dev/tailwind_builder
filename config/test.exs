import Config

# Test environment configuration
# This file is loaded after config.exs

# Configure logger to only show warnings and errors in test
config :logger, level: :warning

# Configure Req for testing with shorter timeouts
config :req,
  timeout: 5_000,
  retry: [
    max_retries: 1,
    retry_delay: fn _attempt -> 50 end
  ]
