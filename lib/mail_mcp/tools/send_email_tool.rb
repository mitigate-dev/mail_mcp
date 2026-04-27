require "mail"

module MailMCP
  class SendEmailTool < Tool
    tool_name "send_email"
    description "Send an email via SMTP"

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
      mail = build_mail(
        from: server_context.imap_config[:username],
        to: to, subject: subject, body: body,
        cc: cc, bcc: bcc, html_body: html_body,
        attachment_urls: attachment_urls
      )
      SmtpClient.send(server_context.smtp_config, mail)
      MCP::Tool::Response.new([{ type: "text", text: "Email sent successfully to #{to}" }])
    end

    def self.build_mail(from:, to:, subject:, body:, cc:, bcc:, html_body:, attachment_urls:)
      mail = Mail.new
      mail.from    = from
      mail.to      = to
      mail.subject = subject
      mail.cc      = cc if cc
      mail.bcc     = bcc if bcc
      if html_body
        mail.html_part = Mail::Part.new do
          content_type "text/html
 charset=UTF-8"
          body html_body
        end
        mail.text_part = Mail::Part.new do
          content_type "text/plain
 charset=UTF-8"
          body body
        end
      else
        mail.body = body
      end
      attachment_urls.each { |url| attach_from_url(mail, url) }
      mail
    end
    private_class_method :build_mail

    def self.attach_from_url(mail, url)
      require "open-uri"
      URI.open(url) do |f|
        filename = File.basename(URI.parse(url).path)
        mail.attachments[filename] = { content: f.read, mime_type: f.content_type }
      end
    rescue StandardError => e
      raise "Failed to fetch attachment from #{url}: #{e.message}"
    end
    private_class_method :attach_from_url
  end
end
