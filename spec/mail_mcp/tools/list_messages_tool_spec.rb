require "spec_helper"

RSpec.describe MailMCP::ListMessagesTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user", password: "pass" }
    )
  end
  let(:imap_client) { instance_spy(MailMCP::ImapClient) }
  let(:messages_result) { { messages: [{ uid: 1, subject: "Hello" }], total: 1, page: 1, per_page: 20 } }

  before do
    allow(MailMCP::ImapClient).to receive(:connect).and_yield(imap_client)
    allow(imap_client).to receive(:list_messages).and_return(messages_result)
  end

  it "passes folder and pagination params to ImapClient" do
    described_class.call(folder: "INBOX", page: 2, per_page: 10, server_context: context)
    expect(imap_client).to have_received(:list_messages).with(folder: "INBOX", page: 2, per_page: 10)
  end

  it "returns paginated messages as JSON text" do
    result = described_class.call(folder: "INBOX", server_context: context).to_h
    expect(result[:content].first[:text]).to include("Hello")
  end
end
