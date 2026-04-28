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

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    def self.smtp_open(config, &)
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
      raise ConnectionError, "SMTP connection failed: #{e.message}"
    end
    private_class_method :smtp_open
  end
end
