module MailMCP
  class MoveMailMessageTool < Tool
    tool_name "move_mail_message"
    description "Move a message to another folder"
    annotations(
      title: "Move Mail Message",
      read_only_hint: false,
      destructive_hint: true,
      idempotent_hint: false,
      open_world_hint: true
    )

    input_schema(
      type: "object",
      properties: {
        folder: { type: "string", description: "Source folder" },
        uid: { type: "integer" },
        destination: { type: "string", description: "Destination folder" }
      },
      required: %w[folder uid destination]
    )

    def self.call(folder:, uid:, destination:, server_context:)
      ImapClient.connect(server_context.imap_config) do |c|
        c.move_message(folder: folder, uid: uid, destination: destination)
      end
      MCP::Tool::Response.new([{ type: "text", text: "Message #{uid} moved from #{folder} to #{destination}" }])
    end
  end
end
