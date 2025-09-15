import Config

# Production environment configuration
# This file is loaded after config.exs

# Configure stricter logging in production
config :logger, level: :info

# Production Req configuration with reasonable timeouts
config :req,
  timeout: 30_000,
  retry: [
    max_retries: 3,
    retry_delay: fn attempt -> 500 * attempt end
  ]

# Ensure all environment variables are available
# These will be validated at runtime
required_env_vars = [
  "AWS_ACCESS_KEY_ID",
  "AWS_SECRET_ACCESS_KEY", 
  "R2_HOST"
]

for var <- required_env_vars do
  if System.get_env(var) == nil do
    raise "Environment variable #{var} is required in production"
  end
end