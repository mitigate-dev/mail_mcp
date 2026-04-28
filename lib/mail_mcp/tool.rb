require "mcp"

module MailMCP
  class Tool < MCP::Tool
    def self.format_from(server_context)
      address = server_context.email
      name = server_context.full_name
      return address if name.nil? || name.empty?

      addr = Mail::Address.new
      addr.address = address
      addr.display_name = name
      addr.format
    end
  end
end
