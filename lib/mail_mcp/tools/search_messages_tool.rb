module MailMCP
  class SearchMessagesTool < Tool
    tool_name "search_messages"
    description "Search messages in an IMAP folder using raw IMAP SEARCH criteria"

    input_schema(
      type: "object",
      properties: {
        folder: { type: "string", description: "Mailbox folder name, e.g. INBOX" },
        query: { type: "string",
                 description: "Raw IMAP SEARCH criteria, e.g. 'UNSEEN' or " \
                              "'FROM alice@example.com SINCE 01-Jan-2025'" }
      },
      required: %w[folder query]
    )

    def self.call(folder:, query:, server_context:)
      uids = ImapClient.connect(server_context.imap_config) { |c| c.search_messages(folder: folder, query: query) }
      MCP::Tool::Response.new([{ type: "text",
                                 text: JSON.generate({ folder: folder, query: query, uids: uids,
                                                       count: uids.length }) }])
    end
  end
end
