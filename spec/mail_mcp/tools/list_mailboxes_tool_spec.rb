require "spec_helper"

RSpec.describe MailMCP::ListMailboxesTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user", password: "pass" }
    )
  end
  let(:imap_client) { instance_spy(MailMCP::ImapClient) }

  before do
    allow(MailMCP::ImapClient).to receive(:connect).and_yield(imap_client)
    allow(imap_client).to receive(:list_mailboxes).and_return(%w[INBOX Sent Drafts])
  end

  it "returns mailbox names as text" do
    result = described_class.call(server_context: context).to_h
    expect(result[:content].first[:text]).to include("INBOX", "Sent", "Drafts")
  end
end
