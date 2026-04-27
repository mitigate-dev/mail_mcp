require "spec_helper"

RSpec.describe MailMCP::SendEmailTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user@example.com", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user@example.com", password: "pass" }
    )
  end

  it "builds a Mail object with the correct fields and sends it" do
    allow(MailMCP::SmtpClient).to receive(:send)
    described_class.call(to: "recipient@example.com", subject: "Hello", body: "World", server_context: context)
    expect(MailMCP::SmtpClient).to have_received(:send) do |_config, mail|
      expect(mail.subject).to eq("Hello")
      expect(mail.to).to include("recipient@example.com")
    end
  end

  it "returns a success message" do
    allow(MailMCP::SmtpClient).to receive(:send)
    result = described_class.call(
      to: "recipient@example.com",
      subject: "Hello",
      body: "World",
      server_context: context
    ).to_h
    expect(result[:content].first[:text]).to match(/sent/i)
  end
end
