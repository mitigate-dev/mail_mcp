require "spec_helper"

RSpec.describe MailMCP::SmtpClient do
  let(:config) do
    {
      host: "smtp.example.com", port: 587, ssl: false,
      username: "user@example.com", password: "secret"
    }
  end
  let(:smtp) { instance_spy(Net::SMTP) }

  before do
    allow(Net::SMTP).to receive(:new).and_return(smtp)
    allow(smtp).to receive(:enable_starttls_auto)
  end

  describe ".validate!" do
    it "opens an SMTP connection" do
      allow(smtp).to receive(:start)
      described_class.validate!(config)
      expect(smtp).to have_received(:start)
    end

    it "raises ConnectionError on failure" do
      allow(smtp).to receive(:start).and_raise(Net::SMTPAuthenticationError, "auth failed")
      expect { described_class.validate!(config) }
        .to raise_error(MailMCP::SmtpClient::ConnectionError)
    end
  end

  describe ".send" do
    it "delivers the message via send_message" do
      allow(smtp).to receive(:start).and_yield(smtp)
      mail = Mail.new
      mail.from = "sender@example.com"
      mail.to = "recipient@example.com"
      mail.subject = "Hello"
      mail.body = "World"
      described_class.send(config, mail)
      expect(smtp).to have_received(:send_message)
    end
  end
end
