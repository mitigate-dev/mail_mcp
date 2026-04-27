module MailMCP
  class GetMessageTool < Tool
    tool_name "get_message"
    description "Fetch a full email message including body and attachment URLs"

    input_schema(
      type: "object",
      properties: {
        folder: { type: "string", description: "Mailbox folder name" },
        uid: { type: "integer", description: "Message UID" }
      },
      required: %w[folder uid]
    )

    def self.call(folder:, uid:, server_context:)
      msg = ImapClient.connect(server_context.imap_config) { |c| c.get_message(folder: folder, uid: uid) }
      return MCP::Tool::Response.new([{ type: "text", text: "Message not found" }], error: true) unless msg

      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(msg) }])
    end
  end
end
