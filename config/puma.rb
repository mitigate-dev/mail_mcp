port        ENV.fetch("PORT", 3000)
environment ENV.fetch("RACK_ENV", "development")

# StreamableHTTPTransport requires a single worker (sessions are in-memory)
workers 0
threads 1, 5

preload_app!
