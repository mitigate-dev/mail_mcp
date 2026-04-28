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
        text_body: { type: "string", description: "Plain-text body" },
        cc: { type: "string" },
        bcc: { type: "string" },
        html_body: { type: "string", description: "HTML body (optional)" },
        attachment_urls: { type: "array", items: { type: "string" },
                           description: "S3 presigned URLs to attach" },
        folder: { type: "string", description: "IMAP folder to save the sent message (default: Sent)",
                  default: "Sent" }
      },
      required: %w[to subject text_body]
    )

    def self.call(to:, subject:, text_body:, server_context:, cc: nil, bcc: nil, html_body: nil,
                  attachment_urls: [], folder: "Sent")
      mail = MailBuilder.build(
        from: server_context.imap_config[:username],
        to: to, subject: subject, text_body: text_body,
        cc: cc, bcc: bcc, html_body: html_body,
        attachment_urls: attachment_urls
      )
      ImapClient.connect(server_context.imap_config) do |c|
        unless c.list_mailboxes.include?(folder)
          raise ImapClient::ConnectionError,
                "IMAP folder #{folder.inspect} does not exist. Use list_mailboxes to see available folders."
        end
      end

      SmtpClient.send(server_context.smtp_config, mail)

      begin
        ImapClient.connect(server_context.imap_config) do |c|
          c.append_message(folder: folder, raw_message: mail.to_s, flags: [:Seen])
        end
      rescue StandardError => e
        MailMCP.logger.warn { "Email sent but failed to save to IMAP folder=#{folder.inspect}: #{e.message}" }
        text = "Email sent successfully to #{to}, but could not be saved to #{folder}: #{e.message}"
        return MCP::Tool::Response.new([{ type: "text", text: text }])
      end

      MCP::Tool::Response.new([{ type: "text", text: "Email sent successfully to #{to} and saved to #{folder}" }])
    end
  end
end
