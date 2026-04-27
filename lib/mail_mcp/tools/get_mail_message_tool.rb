module MailMCP
  class GetMailMessageTool < Tool
    tool_name "get_mail_message"
    description "Fetch a full email message including body and attachment URLs"
    annotations(
      title: "Get Mail Message",
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: false,
      open_world_hint: true
    )

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
