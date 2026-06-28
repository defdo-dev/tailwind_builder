import Config

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :req,
  timeout: 30_000,
  retry: [
    max_retries: 3,
    retry_delay: fn attempt -> 200 * attempt end
  ]
