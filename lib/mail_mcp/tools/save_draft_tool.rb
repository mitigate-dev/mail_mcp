require "mail"

module MailMCP
  class SaveDraftTool < Tool
    tool_name "save_draft"
    description "Save an email as a draft to the Drafts folder via IMAP APPEND"

    input_schema(
      type: "object",
      properties: {
        to: { type: "string" },
        subject: { type: "string" },
        body: { type: "string" },
        cc: { type: "string" },
        html_body: { type: "string" },
        folder: { type: "string", description: "Target folder (default: Drafts)", default: "Drafts" }
      },
      required: %w[to subject body]
    )

    def self.call(to:, subject:, body:, server_context:, cc: nil, html_body: nil, folder: "Drafts")
      imap_config = server_context.imap_config
      mail = Mail.new
      mail.from    = imap_config[:username]
      mail.to      = to
      mail.subject = subject
      mail.cc      = cc if cc
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

      ImapClient.connect(imap_config) { |c| c.append_message(folder: folder, raw_message: mail.to_s) }
      MCP::Tool::Response.new([{ type: "text", text: "Draft saved to #{folder}" }])
    end
  end
end
