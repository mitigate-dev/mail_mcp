require "spec_helper"

RSpec.describe MailMCP::MoveMailMessageTool do
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

  it "moves the message to the destination folder" do
    described_class.call(folder: "INBOX", uid: 3, destination: "Archive", server_context: context)
    expect(imap_client).to have_received(:move_message).with(folder: "INBOX", uid: 3, destination: "Archive")
  end

  it "returns a success message" do
    result = described_class.call(folder: "INBOX", uid: 3, destination: "Archive", server_context: context).to_h
    expect(result[:content].first[:text]).to include("INBOX").and include("Archive")
  end
end
