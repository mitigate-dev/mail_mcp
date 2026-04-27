require "spec_helper"

RSpec.describe MailMCP::SearchMessagesTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user", password: "pass" }
    )
  end
  let(:imap_client) { instance_spy(MailMCP::ImapClient) }

  before do
    allow(MailMCP::ImapClient).to receive(:connect).and_yield(imap_client)
    allow(imap_client).to receive(:search_messages).and_return([1, 5, 9])
  end

  it "passes folder and raw query to ImapClient" do
    described_class.call(folder: "INBOX", query: "UNSEEN", server_context: context)
    expect(imap_client).to have_received(:search_messages).with(folder: "INBOX", query: "UNSEEN")
  end

  it "returns matching UIDs as text" do
    result = described_class.call(folder: "INBOX", query: "UNSEEN", server_context: context).to_h
    expect(result[:content].first[:text]).to include("1", "5", "9")
  end
end
