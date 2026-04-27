require "spec_helper"

RSpec.describe MailMCP::CreateDraftMailMessageTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user@example.com", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user@example.com", password: "pass" }
    )
  end
  let(:imap_client) { instance_spy(MailMCP::ImapClient) }

  before do
    allow(MailMCP::ImapClient).to receive(:connect).and_yield(imap_client)
  end

  it "appends the draft to the Drafts folder by default" do
    described_class.call(to: "recipient@example.com", subject: "Draft", text_body: "Hello", server_context: context)
    expect(imap_client).to have_received(:append_message).with(
      hash_including(folder: "Drafts")
    )
  end

  it "appends to a custom folder when specified" do
    described_class.call(to: "r@example.com", subject: "S", text_body: "B", folder: "MyDrafts", server_context: context)
    expect(imap_client).to have_received(:append_message).with(hash_including(folder: "MyDrafts"))
  end

  it "returns a success message" do
    result = described_class.call(to: "r@example.com", subject: "S", text_body: "B", server_context: context).to_h
    expect(result[:content].first[:text]).to match(/draft saved/i)
  end
end
