require "spec_helper"

RSpec.describe MailMCP::DeleteMessageTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user", password: "pass" }
    )
  end
  let(:imap_client) { instance_spy(MailMCP::ImapClient) }

  before do
    allow(MailMCP::ImapClient).to receive(:connect).and_yield(imap_client)
  end

  it "deletes the message by uid" do
    described_class.call(folder: "INBOX", uid: 7, server_context: context)
    expect(imap_client).to have_received(:delete_message).with(folder: "INBOX", uid: 7)
  end

  it "returns a success message" do
    result = described_class.call(folder: "INBOX", uid: 7, server_context: context).to_h
    expect(result[:content].first[:text]).to include("7").and include("INBOX")
  end
end
