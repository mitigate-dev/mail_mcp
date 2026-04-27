require "mail"
require "open-uri"

module MailMCP
  module MailBuilder
    module_function

    def build(from:, to:, subject:, text_body:, cc: nil, bcc: nil, html_body: nil, attachment_urls: [])
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
          body text_body
        end
      else
        mail.body = text_body
      end
      attachment_urls.each { |url| attach_from_url(mail, url) }
      mail
    end

    def attach_from_url(mail, url)
      URI.open(url) do |f|
        filename = File.basename(URI.parse(url).path)
        mail.attachments[filename] = { content: f.read, mime_type: f.content_type }
      end
    rescue StandardError => e
      raise "Failed to fetch attachment from #{url}: #{e.message}"
    end
  end
end
