import Config

# Development environment configuration
# This file is loaded after config.exs

# For development, you can use local environment variables
# or hardcode values for testing

# Example R2 configuration for development
# config :ex_aws,
#   access_key_id: "your-dev-key-id",
#   secret_access_key: "your-dev-secret",
#   s3: [
#     host: "your-dev-account.r2.cloudflarestorage.com"
#   ]

# Enable verbose logging in development
config :logger, level: :debug

# Req configuration for development
config :req,
  # Longer timeout for development
  timeout: 60_000,
  retry: [
    max_retries: 2,
    retry_delay: fn attempt -> 100 * attempt end
  ]
