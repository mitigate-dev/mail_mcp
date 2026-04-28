module MailMCP
  # Immutable credential value object passed as server_context to each per-request MCP server.
  # MCP::ServerContext delegates imap_config / smtp_config to this via method_missing.
  CredentialContext = Struct.new(:imap_config, :smtp_config, :email, :full_name, keyword_init: true)
end
