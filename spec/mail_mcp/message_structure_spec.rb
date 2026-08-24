require "spec_helper"

RSpec.describe MailMCP::MessageStructure do
  def structure_for(raw)
    server = FakeImapServer.new(raw)
    server.uid_fetch([1], ["BODYSTRUCTURE"]).first.attr["BODYSTRUCTURE"]
  end

  def parts_for(raw)
    described_class.flatten(structure_for(raw))
  end

  def html_part(body)
    part = Mail::Part.new
    part.content_type = "text/html"
    part.body = body
    part
  end

  def png_part(body)
    part = Mail::Part.new
    part.content_type = "image/png"
    part.body = body
    part
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

  # Mail::AttachmentsList only ever treats leaf parts as attachments: a node with
  # children recurses and is never included itself, whatever its disposition says
  # (message/rfc822 is its one special case, and that arrives here as a leaf because
  # BodyTypeMessage#multipart? is false). Descending unconditionally reproduces that.
  it "descends into a multipart that carries its own attachment disposition" do
    inner = Mail::Part.new
    inner.content_type = "multipart/related; boundary=INNER"
    inner.content_disposition = 'attachment; filename="page.mht"'
    inner.add_part(html_part("<p>archived</p>"))
    inner.add_part(png_part("PNGDATA"))

    outer = Mail.new
    outer.from = "a@x.com"
    outer.to = "b@x.com"
    outer.text_part = Mail::Part.new { body "real body" }
    outer.add_part(inner)

    parts = parts_for(outer.to_s)
    expect(parts.map(&:mime_type)).to eq(["text/plain", "text/html", "image/png"])
    expect(parts.map(&:section)).to eq(%w[1 2.1 2.2])
    expect(parts).to all(satisfy { |part| part.filename.nil? })
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

    # net-imap hands back RFC 2231 continuations as separate numbered keys. A plain
    # key lookup misses them, and the attachment then vanishes from the response
    # entirely, since a filename is what marks a part as an attachment.
    it "reassembles an RFC 2231 split filename" do
      params = { "FILENAME*0*" => "utf-8%27%27r%C3%A4ch", "FILENAME*1*" => "nung%2Epdf" }
      disposition = Net::IMAP::ContentDisposition.new("ATTACHMENT", params)
      body = Net::IMAP::BodyTypeBasic.new("APPLICATION", "PDF", nil, nil, nil, "base64", 10,
                                          nil, disposition, nil, nil, nil)

      expect(described_class.flatten(body).first.filename).to eq("rächnung.pdf")
    end

    it "decodes an RFC 2047 encoded filename" do
      disposition = Net::IMAP::ContentDisposition.new(
        "ATTACHMENT", { "FILENAME" => "=?UTF-8?B?csOkY2hudW5nLnBkZg==?=" }
      )
      body = Net::IMAP::BodyTypeBasic.new("APPLICATION", "PDF", nil, nil, nil, "base64", 10,
                                          nil, disposition, nil, nil, nil)

      expect(described_class.flatten(body).first.filename).to eq("rächnung.pdf")
    end

    it "leaves an apostrophe in an ordinary filename alone" do
      disposition = Net::IMAP::ContentDisposition.new("ATTACHMENT", { "FILENAME" => "'quoted'.pdf" })
      body = Net::IMAP::BodyTypeBasic.new("APPLICATION", "PDF", nil, nil, nil, "base64", 10,
                                          nil, disposition, nil, nil, nil)

      expect(described_class.flatten(body).first.filename).to eq("'quoted'.pdf")
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

    # A part whose size the server did not report still streams: the chunk loop
    # terminates on the first empty range rather than on a byte count.
    it "streams a part of unreported size" do
      part = described_class::Part.new(section: "1", encoding: "base64", encoded_size: 0)
      expect(part).to be_streamable
    end

    it "does not stream an encoding it has no incremental decoder for" do
      part = described_class::Part.new(section: "1", encoding: "x-uuencode", encoded_size: 10)
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
