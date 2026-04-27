require "spec_helper"

RSpec.describe MailMCP::GetMessageTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user", password: "pass" }
    )
  end
  let(:imap_client) { instance_spy(MailMCP::ImapClient) }
  let(:message) { { uid: 42, subject: "Test", from: ["sender@example.com"], body: "Hello" } }

  before do
    allow(MailMCP::ImapClient).to receive(:connect).and_yield(imap_client)
  end

  it "fetches the message by uid and returns it as JSON" do
    allow(imap_client).to receive(:get_message).and_return(message)
    result = described_class.call(folder: "INBOX", uid: 42, server_context: context).to_h
    expect(result[:content].first[:text]).to include("Test")
    expect(result[:isError]).to be_falsy
  end

  it "returns an error response when the message is not found" do
    allow(imap_client).to receive(:get_message).and_return(nil)
    result = described_class.call(folder: "INBOX", uid: 99, server_context: context).to_h
    expect(result[:isError]).to be true
    expect(result[:content].first[:text]).to include("not found")
  end
end
