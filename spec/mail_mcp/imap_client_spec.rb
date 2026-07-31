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

  describe "#get_message" do
    let(:attachment_body) { "PDF-CONTENT" * 10 }
    let(:raw_message) do
      mail = Mail.new
      mail.from = "alice@example.com"
      mail.to = "bob@example.com"
      mail.subject = "Invoice"
      mail.text_part = Mail::Part.new { body "see attached" }
      mail.add_file(filename: "invoice.pdf", content: attachment_body)
      mail.to_s
    end

    before do
      fetch_data = instance_double(
        Net::IMAP::FetchData,
        attr: { "RFC822" => raw_message, "FLAGS" => [:Seen] }
      )
      allow(imap).to receive(:uid_fetch).and_return([fetch_data])
      allow(MailMCP::AttachmentStore).to receive(:upload).and_return("https://s3.example.com/invoice.pdf")
    end

    it "returns the message with its attachment metadata" do
      result = described_class.new(imap).get_message(folder: "INBOX", uid: 42)

      expect(result[:subject]).to eq("Invoice")
      expect(result[:attachments]).to contain_exactly(
        {
          filename: "invoice.pdf",
          content_type: a_string_including("application/pdf"),
          size: attachment_body.bytesize,
          url: "https://s3.example.com/invoice.pdf"
        }
      )
    end

    # Mail#decoded re-decodes on every call, so decoding twice doubled the peak
    # memory of the largest allocation in the request path.
    it "decodes each attachment only once" do
      decode_count = 0
      allow_any_instance_of(Mail::Part).to receive(:decoded).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
        # Count only the attachment: format_message legitimately decodes
        # text_part/html_part too, and those are Mail::Part instances as well.
        decode_count += 1 if original.receiver.attachment?
        original.call
      end

      described_class.new(imap).get_message(folder: "INBOX", uid: 42)

      expect(decode_count).to eq(1)
    end

    it "returns nil when the uid is not found" do
      allow(imap).to receive(:uid_fetch).and_return([])
      expect(described_class.new(imap).get_message(folder: "INBOX", uid: 99)).to be_nil
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
