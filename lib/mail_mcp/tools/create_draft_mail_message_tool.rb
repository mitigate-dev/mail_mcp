module MailMCP
  class CreateDraftMailMessageTool < Tool
    tool_name "create_draft_mail_message"
    description "Save an email as a draft to the Drafts folder via IMAP APPEND"
    annotations(
      title: "Create Draft Mail Message",
      read_only_hint: false,
      destructive_hint: false,
      idempotent_hint: false,
      open_world_hint: true
    )

    input_schema(
      type: "object",
      properties: {
        to: { type: "string" },
        subject: { type: "string" },
        body: { type: "string" },
        cc: { type: "string" },
        html_body: { type: "string" },
        attachment_urls: { type: "array", items: { type: "string" },
                           description: "S3 presigned URLs to attach" },
        folder: { type: "string", description: "Target folder (default: Drafts)", default: "Drafts" }
      },
      required: %w[to subject body]
    )

    def self.call(to:, subject:, body:, server_context:, cc: nil, html_body: nil,
                  attachment_urls: [], folder: "Drafts")
      imap_config = server_context.imap_config
      mail = MailBuilder.build(
        from: imap_config[:username],
        to: to, subject: subject, body: body,
        cc: cc, html_body: html_body,
        attachment_urls: attachment_urls
      )
      ImapClient.connect(imap_config) { |c| c.append_message(folder: folder, raw_message: mail.to_s) }
      MCP::Tool::Response.new([{ type: "text", text: "Draft saved to #{folder}" }])
    end
  end
end
