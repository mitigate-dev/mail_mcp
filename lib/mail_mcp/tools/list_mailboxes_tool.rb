module MailMCP
  class ListMailboxesTool < Tool
    tool_name "list_mailboxes"
    description "List all IMAP mailboxes/folders"
    annotations(
      title: "List Mailboxes",
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: false,
      open_world_hint: true
    )

    def self.call(server_context:)
      mailboxes = ImapClient.connect(server_context.imap_config, &:list_mailboxes)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(mailboxes) }])
    end
  end
end
