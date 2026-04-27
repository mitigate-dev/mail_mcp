require "spec_helper"

RSpec.describe MailMCP::UpdateMailMessageFlagsTool do
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

  it "adds flags as symbols" do
    described_class.call(folder: "INBOX", uid: 5, add: ["\\Seen", "\\Flagged"], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      folder: "INBOX", uid: 5, add: %i[\\Seen \\Flagged], remove: []
    )
  end

  it "removes flags as symbols" do
    described_class.call(folder: "INBOX", uid: 5, remove: ["\\Seen"], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      hash_including(remove: [:"\\Seen"])
    )
  end

  it "returns a success message" do
    result = described_class.call(folder: "INBOX", uid: 5, server_context: context).to_h
    expect(result[:content].first[:text]).to include("5")
  end
end
