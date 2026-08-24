require "spec_helper"

RSpec.describe MailMCP::MessageStructure do
  def structure_for(raw)
    server = FakeImapServer.new(raw)
    server.uid_fetch([1], ["BODYSTRUCTURE"]).first.attr["BODYSTRUCTURE"]
  end

  def parts_for(raw)
    described_class.flatten(structure_for(raw))
  end

  it "returns nothing for a nil structure" do
    expect(described_class.flatten(nil)).to eq([])
  end

  # RFC 3501: a non-multipart message's body is section 1.
  it "numbers a single-part message as section 1" do
    mail = Mail.new
    mail.from = "a@x.com"
    mail.to = "b@x.com"
    mail.body = "text"
    raw = mail.to_s
    expect(parts_for(raw).map(&:section)).to eq(["1"])
  end

  it "numbers the children of a top-level multipart without adding a level" do
    raw = Mail.new do
      from "a@x.com"
      to "b@x.com"
      text_part { body "plain" }
      html_part { body "<p>html</p>" }
    end.to_s

    parts = parts_for(raw)
    expect(parts.map(&:section)).to eq(%w[1 2])
    expect(parts.map(&:mime_type)).to eq(["text/plain", "text/html"])
  end

  it "numbers nested multiparts with dotted sections" do
    inner = Mail::Part.new do
      content_type "multipart/alternative"
      text_part { body "plain" }
      html_part { body "<p>html</p>" }
    end
    outer = Mail.new do
      from "a@x.com"
      to "b@x.com"
      content_type "multipart/mixed"
    end
    outer.add_part(inner)
    outer.add_file(filename: "a.pdf", content: "PDF")

    expect(parts_for(outer.to_s).map(&:section)).to eq(%w[1.1 1.2 2])
  end

  describe "attachment detection" do
    it "treats a part with a filename as an attachment" do
      mail = Mail.new do
        from "a@x.com"
        to "b@x.com"
        text_part { body "see attached" }
      end
      mail.add_file(filename: "invoice.pdf", content: "PDF")

      parts = parts_for(mail.to_s)
      expect(parts.reject(&:attachment?).map(&:mime_type)).to eq(["text/plain"])
      expect(parts.select(&:attachment?).map(&:filename)).to eq(["invoice.pdf"])
    end

    it "reads a filename that the server reported in upper case" do
      mail = Mail.new do
        from "a@x.com"
        to "b@x.com"
        text_part { body "body" }
      end
      mail.add_file(filename: "report.csv", content: "a,b")

      # FakeImapServer upcases parameter names the way real servers do.
      expect(parts_for(mail.to_s).find(&:attachment?).filename).to eq("report.csv")
    end
  end

  describe "streamability" do
    it "streams base64 and identity encodings" do
      %w[base64 7bit 8bit binary].each do |encoding|
        part = described_class::Part.new(section: "1", encoding: encoding, encoded_size: 10)
        expect(part).to be_streamable, "expected #{encoding} to stream"
      end
    end

    it "does not stream quoted-printable, which needs a single-pass decode" do
      part = described_class::Part.new(section: "1", encoding: "quoted-printable", encoded_size: 10)
      expect(part).not_to be_streamable
    end

    # Without a size from the server the chunk loop has no bound to walk.
    it "does not stream a part of unreported size" do
      part = described_class::Part.new(section: "1", encoding: "base64", encoded_size: 0)
      expect(part).not_to be_streamable
    end
  end

  it "exposes the charset so the body can be converted to UTF-8" do
    raw = Mail.new do
      from "a@x.com"
      to "b@x.com"
      content_type "text/plain; charset=ISO-8859-1"
      body "text"
    end.to_s

    expect(parts_for(raw).first.charset).to eq("ISO-8859-1")
  end
end
