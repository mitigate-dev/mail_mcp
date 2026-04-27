module MailMCP
  class SendMailMessageTool < Tool
    tool_name "send_mail_message"
    description "Send an email via SMTP"
    annotations(
      title: "Send Mail Message",
      read_only_hint: false,
      destructive_hint: true,
      idempotent_hint: false,
      open_world_hint: true
    )

    input_schema(
      type: "object",
      properties: {
        to: { type: "string", description: "Recipient address(es), comma-separated" },
        subject: { type: "string" },
        body: { type: "string", description: "Plain-text body" },
        cc: { type: "string" },
        bcc: { type: "string" },
        html_body: { type: "string", description: "HTML body (optional)" },
        attachment_urls: { type: "array", items: { type: "string" },
                           description: "S3 presigned URLs to attach" }
      },
      required: %w[to subject body]
    )

    def self.call(to:, subject:, body:, server_context:, cc: nil, bcc: nil, html_body: nil, attachment_urls: [])
      mail = MailBuilder.build(
        from: server_context.imap_config[:username],
        to: to, subject: subject, body: body,
        cc: cc, bcc: bcc, html_body: html_body,
        attachment_urls: attachment_urls
      )
      SmtpClient.send(server_context.smtp_config, mail)
      MCP::Tool::Response.new([{ type: "text", text: "Email sent successfully to #{to}" }])
    end
  end
end
