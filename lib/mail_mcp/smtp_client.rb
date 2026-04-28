require "net/smtp"

module MailMCP
  module SmtpClient
    class ConnectionError < StandardError; end

    def self.validate!(config)
      smtp_open(config) { nil }
    end

    def self.send(config, mail)
      smtp_open(config) do |s|
        recipients = mail.destinations
        MailMCP.logger.info do
          "SMTP send to=#{recipients.join(",")} from=#{mail.from&.first} subject=#{mail.subject.inspect}"
        end
        s.send_message(encoded_for_wire(mail), mail.from.first, recipients)
      end
    rescue Net::SMTPError, SocketError => e
      MailMCP.logger.error { "SMTP send failed: #{e.class}: #{e.message}" }
      raise ConnectionError, "SMTP send failed: #{e.message}"
    end

    def self.encoded_for_wire(mail)
      return mail.encoded if mail.bcc.nil? || mail.bcc.empty?

      wire = Mail.new(mail.encoded)
      wire.bcc = nil
      wire.encoded
    end
    private_class_method :encoded_for_wire

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    def self.smtp_open(config, &)
      MailMCP.logger.debug do
        "SMTP connect host=#{config[:host]} port=#{config[:port]} ssl=#{config[:ssl]} user=#{config[:username]}"
      end
      smtp = Net::SMTP.new(config[:host], config[:port])
      smtp.open_timeout = OPEN_TIMEOUT
      smtp.read_timeout = READ_TIMEOUT
      if config[:ssl]
        smtp.enable_tls
      else
        smtp.enable_starttls_auto
      end
      smtp.start(config[:host], config[:username], config[:password], :login, &)
    rescue StandardError => e
      MailMCP.logger.error do
        "SMTP connection failed host=#{config[:host]}:#{config[:port]} ssl=#{config[:ssl]}: #{e.class}: #{e.message}"
      end
      raise ConnectionError, "SMTP connection failed: #{e.message}"
    end
    private_class_method :smtp_open
  end
end
