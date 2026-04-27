require "spec_helper"

RSpec.describe MailMCP::ImapClient do
  let(:config) do
    {
      host: "imap.example.com", port: 993, ssl: true,
      username: "user@example.com", password: "secret"
    }
  end
  let(:imap) { instance_spy(Net::IMAP) }

  before do
    allow(Net::IMAP).to receive(:new).and_return(imap)
  end

  describe ".validate!" do
    it "connects, logs in, and disconnects" do
      described_class.validate!(config)
      expect(imap).to have_received(:login).with("user@example.com", "secret")
      expect(imap).to have_received(:logout)
      expect(imap).to have_received(:disconnect)
    end

    it "raises on login failure" do
      allow(imap).to receive(:login).and_raise(Net::IMAP::Error, "authentication failed")
      expect { described_class.validate!(config) }.to raise_error(MailMCP::ImapClient::ConnectionError)
    end
  end

  describe ".connect" do
    it "yields a client wrapping the connection then disconnects" do
      described_class.connect(config) do |client|
        expect(client).to be_a(described_class)
        expect(client.imap).to be(imap)
      end
      expect(imap).to have_received(:logout)
      expect(imap).to have_received(:disconnect)
    end
  end

  describe "#list_mailboxes" do
    it "returns folder names from IMAP LIST" do
      mailboxes = [
        instance_double(Net::IMAP::MailboxList, name: "INBOX"),
        instance_double(Net::IMAP::MailboxList, name: "Sent")
      ]
      allow(imap).to receive(:list).with("", "*").and_return(mailboxes)
      client = described_class.new(imap)
      expect(client.list_mailboxes).to eq(%w[INBOX Sent])
    end
  end

  describe "#search_messages" do
    it "passes raw query string to IMAP SEARCH" do
      allow(imap).to receive(:search).with(["UNSEEN"]).and_return([1, 2, 3])
      client = described_class.new(imap)
      result = client.search_messages(folder: "INBOX", query: "UNSEEN")
      expect(result).to eq([1, 2, 3])
    end

    it "supports multi-word criteria" do
      allow(imap).to receive(:search).with(["FROM", "alice@example.com"]).and_return([5])
      client = described_class.new(imap)
      result = client.search_messages(folder: "INBOX", query: "FROM alice@example.com")
      expect(result).to eq([5])
    end
  end
end
