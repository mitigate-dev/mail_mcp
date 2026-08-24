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
    let(:uploaded) { [] }
    let(:raw_message) do
      mail = Mail.new
      mail.from = "alice@example.com"
      mail.to = "bob@example.com"
      mail.subject = "Invoice"
      mail.text_part = Mail::Part.new { body "see attached" }
      mail.add_file(filename: "invoice.pdf", content: attachment_body)
      mail.to_s
    end
    let(:server) { FakeImapServer.new(raw_message) }

    before do
      allow(MailMCP::AttachmentStore).to receive(:upload_io) do |io:, filename:, **|
        io.rewind
        uploaded << { filename: filename, bytes: io.read }
        "https://s3.example.com/#{filename}"
      end
    end

    it "returns the message with its attachment metadata" do
      result = described_class.new(server).get_message(folder: "INBOX", uid: 42)

      expect(result[:subject]).to eq("Invoice")
      expect(result[:text_body]).to eq("see attached")
      expect(result[:attachments]).to contain_exactly(
        {
          filename: "invoice.pdf",
          content_type: "application/pdf",
          size: attachment_body.bytesize,
          url: "https://s3.example.com/invoice.pdf"
        }
      )
    end

    it "uploads the attachment bytes intact" do
      described_class.new(server).get_message(folder: "INBOX", uid: 42)
      expect(uploaded.first[:bytes]).to eq(attachment_body)
    end

    # The whole point of the per-part path: RFC822 pulls the entire message into one
    # String, which is what made peak memory scale with message size.
    it "never fetches the whole message" do
      described_class.new(server).get_message(folder: "INBOX", uid: 42)
      sections = server.fetches.map(&:first)
      expect(sections).to include("HEADER")
      expect(sections).not_to include("", "TEXT")
    end

    # BODY[...] implicitly sets \Seen; BODY.PEEK[...] does not.
    it "requests every body section with PEEK so reading cannot set flags" do
      described_class.new(server).get_message(folder: "INBOX", uid: 42)
      body_specs = server.requested_specs.grep(/\ABODY(\.PEEK)?\[/)

      expect(body_specs).not_to be_empty
      expect(body_specs).to all(start_with("BODY.PEEK["))
    end

    # A missing section mid-stream used to produce a zero-byte attachment with a
    # valid-looking presigned URL. Failing loudly beats uploading a truncated file.
    it "raises rather than uploading a truncated attachment when a section is missing" do
      allow(server).to receive(:uid_fetch).and_wrap_original do |original, uids, specs|
        specs.any? { |spec| spec.start_with?("BODY.PEEK[2]") } ? [] : original.call(uids, specs)
      end

      expect { described_class.new(server).get_message(folder: "INBOX", uid: 42) }
        .to raise_error(MailMCP::MessageReader::IncompletePart, /BODY\[2\]/)
      expect(uploaded).to be_empty
    end

    it "returns nil when the uid is not found" do
      allow(server).to receive(:uid_fetch).and_return([])
      expect(described_class.new(server).get_message(folder: "INBOX", uid: 99)).to be_nil
    end

    context "with a single-part message" do
      let(:raw_message) do
        mail = Mail.new
        mail.from = "alice@example.com"
        mail.to = "bob@example.com"
        mail.subject = "Plain"
        mail.body = "just text"
        mail.to_s
      end

      # Mail#text_part searches all_parts, which is empty for a non-multipart message,
      # so the previous whole-message implementation returned no body at all here.
      it "returns the body" do
        result = described_class.new(server).get_message(folder: "INBOX", uid: 42)
        expect(result[:text_body]).to eq("just text")
        expect(result[:attachments]).to be_empty
      end
    end

    context "with a non-UTF-8 body" do
      let(:raw_message) do
        mail = Mail.new
        mail.from = "alice@example.com"
        mail.to = "bob@example.com"
        mail.subject = "Latin"
        mail.content_type = "text/plain; charset=ISO-8859-1"
        mail.content_transfer_encoding = "8bit"
        mail.body = "caf\xE9 cr\xE8me".dup.force_encoding("ASCII-8BIT")
        mail.to_s
      end

      it "converts the body to UTF-8" do
        result = described_class.new(server).get_message(folder: "INBOX", uid: 42)
        expect(result[:text_body]).to eq("café crème")
      end
    end

    context "with an attachment larger than one chunk" do
      let(:attachment_body) { "0123456789abcdef" * 700_000 }

      it "fetches it in byte ranges and reassembles it exactly" do
        described_class.new(server).get_message(folder: "INBOX", uid: 42)

        expect(server.partial_fetches.size).to be > 1
        expect(uploaded.first[:bytes].bytesize).to eq(attachment_body.bytesize)
        expect(uploaded.first[:bytes]).to eq(attachment_body)
      end
    end

    context "with a quoted-printable attachment" do
      let(:raw_message) do
        mail = Mail.new
        mail.from = "alice@example.com"
        mail.to = "bob@example.com"
        mail.subject = "QP"
        mail.text_part = Mail::Part.new { body "body" }
        mail.attachments["notes.txt"] = { content: "line = one\r\n" * 20,
                                          transfer_encoding: "quoted-printable" }
        mail.to_s
      end

      it "decodes it in a single pass" do
        described_class.new(server).get_message(folder: "INBOX", uid: 42)
        expect(uploaded.first[:bytes]).to include("line = one")
      end
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
