module MailMCP
  class UpdateMailMessageFlagsTool < Tool
    tool_name "update_mail_message_flags"
    description "Update IMAP flags on a message (mark as read, flagged, etc.)"

    input_schema(
      type: "object",
      properties: {
        folder: { type: "string" },
        uid: { type: "integer" },
        add: { type: "array", items: { type: "string" },
               description: "Flags to add, e.g. ['\\\\Seen', '\\\\Flagged']" },
        remove: { type: "array", items: { type: "string" }, description: "Flags to remove" }
      },
      required: %w[folder uid]
    )

    def self.call(folder:, uid:, server_context:, add: [], remove: [])
      add_flags    = add.map(&:to_sym)
      remove_flags = remove.map(&:to_sym)
      ImapClient.connect(server_context.imap_config) do |c|
        c.update_flags(folder: folder, uid: uid, add: add_flags, remove: remove_flags)
      end
      MCP::Tool::Response.new([{ type: "text", text: "Flags updated for message #{uid}" }])
    end
  end
end
