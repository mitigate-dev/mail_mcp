module MailMCP
  class ListMailMessagesTool < Tool
    tool_name "list_mail_messages"
    description "List messages in an IMAP folder with pagination"
    annotations(
      title: "List Mail Messages",
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: false,
      open_world_hint: true
    )

    input_schema(
      type: "object",
      properties: {
        folder: { type: "string", description: "Mailbox folder name" },
        page: { type: "integer", description: "Page number (default 1)", default: 1 },
        per_page: { type: "integer", description: "Messages per page (default 20)", default: 20 }
      },
      required: ["folder"]
    )

    def self.call(folder:, server_context:, page: 1, per_page: 20)
      result = ImapClient.connect(server_context.imap_config) do |c|
        c.list_messages(folder: folder, page: page, per_page: per_page)
      end
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(result) }])
    end
  end
end
