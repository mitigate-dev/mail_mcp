module MailMCP
  class DeleteMailMessageTool < Tool
    tool_name "delete_mail_message"
    description "Delete a message by UID (marks as deleted and expunges)"
    annotations(
      title: "Delete Mail Message",
      read_only_hint: false,
      destructive_hint: true,
      idempotent_hint: false,
      open_world_hint: true
    )

    input_schema(
      type: "object",
      properties: {
        folder: { type: "string" },
        uid: { type: "integer" }
      },
      required: %w[folder uid]
    )

    def self.call(folder:, uid:, server_context:)
      ImapClient.connect(server_context.imap_config) { |c| c.delete_message(folder: folder, uid: uid) }
      MCP::Tool::Response.new([{ type: "text", text: "Message #{uid} deleted from #{folder}" }])
    end
  end
end
