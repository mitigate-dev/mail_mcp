require "net/smtp"

module MailMCP
  module SmtpClient
    class ConnectionError < StandardError; end

    def self.validate!(config)
      smtp_open(config) { nil }
    end

    def self.send(config, mail)
      smtp_open(config) do |s|
        s.send_message(mail.to_s, mail.from.first, mail.to)
      end
    rescue Net::SMTPError, SocketError => e
      raise ConnectionError, "SMTP send failed: #{e.message}"
    end

    def self.smtp_open(config, &)
      smtp = Net::SMTP.new(config[:host], config[:port])
      smtp.enable_starttls_auto unless config[:ssl]
      smtp.start(config[:host], config[:username], config[:password], :login, &)
    rescue StandardError => e
      raise ConnectionError, "SMTP connection failed: #{e.message}"
    end
    private_class_method :smtp_open
  end
end
