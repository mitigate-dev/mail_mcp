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
        text_body: { type: "string" },
        cc: { type: "string" },
        bcc: { type: "string" },
        html_body: { type: "string" },
        attachment_urls: { type: "array", items: { type: "string" },
                           description: "S3 presigned URLs to attach" },
        folder: { type: "string", description: "Target folder (default: Drafts)", default: "Drafts" }
      },
      required: %w[to subject text_body]
    )

    def self.call(to:, subject:, text_body:, server_context:, cc: nil, bcc: nil, html_body: nil,
                  attachment_urls: [], folder: "Drafts")
      mail = MailBuilder.build(
        from: format_from(server_context),
        to: to, subject: subject, text_body: text_body,
        cc: cc, bcc: bcc, html_body: html_body,
        attachment_urls: attachment_urls
      )
      ImapClient.connect(server_context.imap_config) do |c|
        c.append_message(folder: folder, raw_message: mail.to_s, flags: [:Draft])
      end
      MCP::Tool::Response.new([{ type: "text", text: "Draft saved to #{folder}" }])
    end
  end
end
