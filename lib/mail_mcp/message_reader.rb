require "tempfile"

module MailMCP
  # Reads one message over an existing IMAP connection a part at a time, so peak memory
  # tracks the part being handled rather than the size of the whole message. Fetching
  # RFC822 instead would materialize the entire message as a single String.
  class MessageReader
    # Raised when the server answers a section fetch with a section we did not ask for.
    # Treated as an error because the alternative is a silently truncated attachment.
    class IncompletePart < StandardError; end

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

      to_h(headers: Mail.new(data.header.to_s), flags: data.attr["FLAGS"], parts: parts)
    end

    private

    def to_h(headers:, flags:, parts:)
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

    # Letting Mail decode a rebuilt part applies both the transfer-encoding and the
    # charset conversion, which is what #decoded did on the old whole-message parse.
    # Hand-rolling that would mislabel any non-UTF-8 body.
    def decode_inline(part, body)
      rebuilt = Mail::Part.new
      rebuilt.content_type = part.charset ? "#{part.mime_type}; charset=#{part.charset}" : part.mime_type
      rebuilt.content_transfer_encoding = part.encoding
      rebuilt.body = body
      rebuilt.decoded
    rescue StandardError => e
      MailMCP.logger.warn { "IMAP inline decode failed section=#{part.section}: #{e.class}: #{e.message}" }
      nil
    end

    # Each attachment is streamed to disk, uploaded, then discarded before the next is
    # fetched, so attachments never accumulate in memory.
    def upload_attachments(parts)
      parts.map do |part|
        Tempfile.create("mail_mcp_attachment", binmode: true) do |io|
          size = fetch_attachment(io, part)
          url = AttachmentStore.upload_io(
            io: io,
            filename: part.filename || "attachment",
            content_type: part.mime_type
          )
          { filename: part.filename, content_type: part.mime_type, size: size, url: url }
        end
      end
    end

    # Returns the decoded byte count written to +io+.
    def fetch_attachment(io, part)
      return stream_section(io, part) if part.streamable?

      # Quoted-printable has to be decoded in one pass, so this path is bounded by the
      # part size rather than by CHUNK_SIZE. Logged because it is the one place where
      # the memory guarantee above does not hold.
      MailMCP.logger.warn do
        "IMAP attachment decoded in one pass encoding=#{part.encoding.inspect} " \
          "encoded_size=#{part.encoded_size} section=#{part.section}"
      end
      io.write(decode_whole(require_section(part.section), part.encoding))
    end

    def stream_section(io, part)
      decoder = part.base64? ? Base64Stream.new : nil
      offset = 0
      written = 0
      loop do
        fetched, wrote = consume_chunk(io, decoder, part, offset)
        break if fetched.zero?

        offset += fetched
        written += wrote
      end
      written += io.write(decoder.finish) if decoder
      written
    end

    # Kept in its own method so the chunk becomes unreachable as soon as it returns.
    # Held in a local in the loop above, a CHUNK_SIZE buffer would stay alive across
    # the next fetch, doubling the resident cost of streaming.
    # Returns [encoded bytes fetched, decoded bytes written].
    def consume_chunk(io, decoder, part, offset)
      chunk = require_section(part.section, offset: offset)
      return [0, 0] if chunk.empty?

      # #push consumes the chunk, so read its size before handing it over.
      fetched = chunk.bytesize
      [fetched, io.write(decoder ? decoder.push(chunk) : chunk)]
    end

    def decode_whole(raw, encoding)
      encoder = Mail::Encodings.get_encoding(encoding)
      encoder ? encoder.decode(raw) : raw
    rescue StandardError => e
      MailMCP.logger.warn { "IMAP attachment decode failed encoding=#{encoding.inspect}: #{e.class}: #{e.message}" }
      raw
    end

    def require_section(section, offset: nil)
      fetch_section(section, offset: offset) ||
        raise(IncompletePart, "IMAP returned no BODY[#{section}] at offset #{offset.inspect} for uid #{@uid}")
    end

    # net-imap reconciles the request spec against the response key, which differ:
    # servers answer BODY.PEEK[...] with BODY[...] and append the origin octet on a
    # partial fetch. A nil result means a section we did not ask for.
    def fetch_section(section, offset: nil)
      spec = offset ? "BODY.PEEK[#{section}]<#{offset}.#{CHUNK_SIZE}>" : "BODY.PEEK[#{section}]"
      data = @imap.uid_fetch([@uid], [spec])&.first
      data&.part(*section.split("."), offset: offset)
    end
  end
end
