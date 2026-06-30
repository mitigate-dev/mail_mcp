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

  it "adds system flags as symbols (so net/imap renders them with a backslash)" do
    described_class.call(folder: "INBOX", uid: 5, add: ["\\Seen", "\\Flagged"], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      folder: "INBOX", uid: 5, add: %i[Seen Flagged], remove: []
    )
  end

  it "removes system flags as symbols" do
    described_class.call(folder: "INBOX", uid: 5, remove: ["\\Seen"], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      hash_including(remove: [:Seen])
    )
  end

  it "passes custom keywords (e.g. colors) as strings, not system-flag symbols" do
    described_class.call(folder: "INBOX", uid: 5, add: ["YELLOW", "$label1"], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      hash_including(add: ["YELLOW", "$label1"])
    )
  end

  it "treats system flag names without a backslash as system flags" do
    described_class.call(folder: "INBOX", uid: 5, add: ["Seen"], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      hash_including(add: [:Seen])
    )
  end

  it "matches system flags case-insensitively and normalizes capitalization" do
    described_class.call(folder: "INBOX", uid: 5, add: ["\\seen", "FLAGGED"], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      hash_including(add: %i[Seen Flagged])
    )
  end

  it "maps friendly color names to $labelN keywords" do
    described_class.call(folder: "INBOX", uid: 5, add: %w[red blue], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      hash_including(add: ["$label1", "$label4"])
    )
  end

  it "maps color names case-insensitively, including on remove" do
    described_class.call(folder: "INBOX", uid: 5, remove: ["GREEN"], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      hash_including(remove: ["$label3"])
    )
  end

  it "passes raw $labelN keywords through unchanged" do
    described_class.call(folder: "INBOX", uid: 5, add: %w[$label1 $label5], server_context: context)
    expect(imap_client).to have_received(:update_flags).with(
      hash_including(add: %w[$label1 $label5])
    )
  end

  it "returns a success message" do
    result = described_class.call(folder: "INBOX", uid: 5, server_context: context).to_h
    expect(result[:content].first[:text]).to include("5")
  end
end
