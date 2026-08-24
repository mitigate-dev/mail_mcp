require "tempfile"

module MailMCP
  # Reads one message over an existing IMAP connection a part at a time, so peak memory
  # tracks the part being handled rather than the size of the whole message. Fetching
  # RFC822 instead would materialize the entire message as a single String.
  class MessageReader
    # Encoded bytes pulled per FETCH when streaming an attachment. Bounds peak memory
    # regardless of attachment size; larger chunks mean fewer round trips but hold a
    # Puma thread for longer.
    CHUNK_SIZE = 4 * 1024 * 1024

    def initialize(imap, uid)
      @imap = imap
      @uid = uid
    end

    # Returns the message as the tool-facing hash, or nil when the uid is gone.
    def read
      data = @imap.uid_fetch([@uid], ["BODYSTRUCTURE", "FLAGS", "BODY.PEEK[HEADER]"])&.first
      return nil unless data

      parts = MessageStructure.flatten(data.attr["BODYSTRUCTURE"])
      MailMCP.logger.debug { "IMAP message uid=#{@uid} parts=#{parts.map(&:section).inspect}" }

      format(
        headers: Mail.new(self.class.body_of(data.attr, "HEADER").to_s),
        flags: data.attr["FLAGS"],
        parts: parts
      )
    end

    # Servers answer BODY.PEEK[...] with BODY[...], and append the origin octet on a
    # partial fetch (BODY[1]<0>), so the response key never matches the request.
    def self.body_of(attrs, section)
      exact = attrs["BODY[#{section}]"]
      return exact if exact

      prefix = "BODY[#{section}]<"
      attrs.find { |key, _value| key.to_s.start_with?(prefix) }&.last
    end

    private

    def format(headers:, flags:, parts:)
      inline = parts.reject(&:attachment?)
      {
        uid: @uid,
        message_id: headers.message_id,
        in_reply_to: headers.in_reply_to,
        references: headers.references,
        subject: headers.subject,
        from: headers.from,
        sender: headers.sender,
        reply_to: headers.reply_to,
        to: headers.to,
        cc: headers.cc,
        bcc: headers.bcc,
        date: headers.date&.iso8601,
        text_body: inline_body(inline, "text/plain"),
        html_body: inline_body(inline, "text/html"),
        flags: flags,
        attachments: upload_attachments(parts.select(&:attachment?))
      }
    end

    # Mail#text_part/#html_part pick the first non-attachment part of that type, so
    # match the flattened list the same way.
    def inline_body(inline, mime_type)
      part = inline.find { |candidate| candidate.mime_type == mime_type }
      return nil unless part

      body = fetch_section(part.section)
      body && decode_inline(part, body)
    end

    # Rebuilding the part from a synthesized MIME header lets Mail apply both the
    # transfer-encoding and the charset conversion, which is what #decoded did on the
    # old whole-message parse. Hand-rolling that would mislabel any non-UTF-8 body.
    def decode_inline(part, body)
      header = "Content-Type: #{part.mime_type}"
      header += "; charset=#{part.charset}" if part.charset
      header += "\r\nContent-Transfer-Encoding: #{part.encoding}\r\n"
      Mail::Part.new("#{header}\r\n#{body}").decoded
    rescue StandardError => e
      MailMCP.logger.warn { "IMAP inline decode failed section=#{part.section}: #{e.class}: #{e.message}" }
      nil
    end

    # Each attachment is streamed to disk, uploaded, then discarded before the next is
    # fetched, so attachments never accumulate in memory.
    def upload_attachments(parts)
      parts.map do |part|
        tempfile = fetch_attachment(part)
        begin
          url = AttachmentStore.upload_io(
            io: tempfile,
            filename: part.filename || "attachment",
            content_type: part.mime_type
          )
          { filename: part.filename, content_type: part.mime_type, size: tempfile.size, url: url }
        ensure
          tempfile.close!
        end
      end
    end

    def fetch_attachment(part)
      tempfile = Tempfile.new("mail_mcp_attachment")
      tempfile.binmode
      if part.streamable?
        stream_section(tempfile, part)
      else
        # Quoted-printable, or a part whose size the server did not report. Neither is
        # used for large payloads in practice, so one pass is acceptable here.
        tempfile.write(decode_whole(fetch_section(part.section).to_s, part.encoding))
      end
      tempfile.flush
      tempfile
    end

    def stream_section(tempfile, part)
      decoder = part.base64? ? Base64Stream.new : nil
      offset = 0
      # Bounded by the size BODYSTRUCTURE reported; the empty check is a second guard so
      # a server returning short reads cannot spin here.
      while offset < part.encoded_size
        chunk = fetch_section(part.section, offset: offset, length: CHUNK_SIZE)
        break if chunk.nil? || chunk.empty?

        tempfile.write(decoder ? decoder.push(chunk) : chunk)
        offset += chunk.bytesize
      end
      tempfile.write(decoder.finish) if decoder
    end

    def decode_whole(raw, encoding)
      encoder = Mail::Encodings.get_encoding(encoding)
      encoder ? encoder.decode(raw) : raw
    rescue StandardError => e
      MailMCP.logger.warn { "IMAP attachment decode failed encoding=#{encoding.inspect}: #{e.class}: #{e.message}" }
      raw
    end

    def fetch_section(section, offset: nil, length: nil)
      spec = offset ? "BODY.PEEK[#{section}]<#{offset}.#{length}>" : "BODY.PEEK[#{section}]"
      data = @imap.uid_fetch([@uid], [spec])&.first
      data && self.class.body_of(data.attr, section)
    end
  end
end
