require "spec_helper"

RSpec.describe MailMCP::SendMailMessageTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user@example.com", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user@example.com", password: "pass" }
    )
  end
  let(:imap_client) { instance_spy(MailMCP::ImapClient) }

  before do
    allow(MailMCP::SmtpClient).to receive(:send)
    allow(MailMCP::ImapClient).to receive(:connect).and_yield(imap_client)
    allow(imap_client).to receive(:list_mailboxes).and_return(["INBOX", "Sent", "Sent Items"])
  end

  it "builds a Mail object with the correct fields and sends it" do
    described_class.call(to: "recipient@example.com", subject: "Hello", text_body: "World", server_context: context)
    expect(MailMCP::SmtpClient).to have_received(:send) do |_config, mail|
      expect(mail.subject).to eq("Hello")
      expect(mail.to).to include("recipient@example.com")
    end
  end

  it "appends the sent message to the Sent folder by default" do
    described_class.call(to: "r@example.com", subject: "S", text_body: "B", server_context: context)
    expect(imap_client).to have_received(:append_message).with(hash_including(folder: "Sent"))
  end

  it "appends to a custom folder when specified" do
    described_class.call(to: "r@example.com", subject: "S", text_body: "B",
                         folder: "Sent Items", server_context: context)
    expect(imap_client).to have_received(:append_message).with(hash_including(folder: "Sent Items"))
  end

  it "returns a success message" do
    result = described_class.call(
      to: "recipient@example.com",
      subject: "Hello",
      text_body: "World",
      server_context: context
    ).to_h
    expect(result[:content].first[:text]).to match(/sent/i)
  end
end
