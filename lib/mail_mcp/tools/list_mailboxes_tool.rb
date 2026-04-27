module MailMCP
  class ListMailboxesTool < Tool
    tool_name "list_mailboxes"
    description "List all IMAP mailboxes/folders"

    def self.call(server_context:)
      mailboxes = ImapClient.connect(server_context.imap_config, &:list_mailboxes)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(mailboxes) }])
    end
  end
end
