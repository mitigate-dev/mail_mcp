require "net/imap"

# Serves BODYSTRUCTURE and BODY[...] fetches for a real RFC822 message, the way an
# IMAP server would. Addressing is derived from Mail's own part tree rather than from
# MailMCP::MessageStructure, so specs exercise the walker instead of confirming itself.
class FakeImapServer
  attr_reader :fetches, :requested_specs

  def initialize(raw)
    @mail = Mail.new(raw)
    @fetches = []
    @requested_specs = []
  end

  def examine(_folder) = nil

  def select(_folder) = nil

  def uid_fetch(_uids, specs)
    @requested_specs.concat(specs)
    attrs = specs.each_with_object({}) { |spec, acc| serve(spec, acc) }
    return nil if attrs.empty?

    [Struct.new(:attr).new(attrs)]
  end

  # Sections fetched with a byte range, e.g. [["2", 0, 4194304]].
  def partial_fetches
    @fetches.select { |_section, offset, _length| offset }
  end

  private

  def serve(spec, acc)
    case spec
    when "BODYSTRUCTURE" then acc["BODYSTRUCTURE"] = structure_of(@mail)
    when "FLAGS" then acc["FLAGS"] = [:Seen]
    when /\ABODY\.PEEK\[(.+?)\](?:<(\d+)\.(\d+)>)?\z/
      serve_body(acc, Regexp.last_match(1), Regexp.last_match(2)&.to_i, Regexp.last_match(3)&.to_i)
    end
  end

  def serve_body(acc, section, offset, length)
    @fetches << [section, offset, length]
    body = section_bytes(section)
    return if body.nil?

    if offset
      acc["BODY[#{section}]<#{offset}>"] = body.byteslice(offset, length) || +""
    else
      acc["BODY[#{section}]"] = body
    end
  end

  def section_bytes(section)
    return "#{@mail.header.raw_source}\r\n" if section == "HEADER"

    locate(section)&.body&.raw_source
  end

  # RFC 3501 part addressing: a single-part message is section 1; otherwise walk the
  # dotted index path through the multipart tree.
  def locate(section)
    indices = section.split(".").map { |number| number.to_i - 1 }
    return indices == [0] ? @mail : nil unless @mail.multipart?

    indices.reduce(@mail) do |node, index|
      child = descend(node, index)
      return nil if child.nil?

      child
    end
  end

  def descend(node, index)
    return nil unless node.respond_to?(:multipart?) && node.multipart?

    node.parts[index]
  end

  def structure_of(part)
    return leaf_of(part) unless part.multipart?

    Net::IMAP::BodyTypeMultipart.new(
      "MULTIPART", part.mime_type.to_s.split("/").last.to_s.upcase,
      part.parts.map { |child| structure_of(child) },
      params_of(part), disposition_of(part), nil, nil, nil
    )
  end

  def leaf_of(part)
    media, sub = (part.mime_type || "text/plain").split("/")
    size = part.body.raw_source.bytesize
    shared = [media.to_s.upcase, sub.to_s.upcase, params_of(part), part.content_id, nil,
              (part.content_transfer_encoding || "7bit").to_s, size]
    if media.to_s.casecmp?("text")
      Net::IMAP::BodyTypeText.new(*shared, part.body.raw_source.count("\n"), nil,
                                  disposition_of(part), nil, nil, nil)
    else
      Net::IMAP::BodyTypeBasic.new(*shared, nil, disposition_of(part), nil, nil, nil)
    end
  end

  # Upcased on purpose: real servers pick their own case for parameter names.
  def params_of(part)
    (part.content_type_parameters || {}).transform_keys { |key| key.to_s.upcase }
  rescue StandardError
    {}
  end

  def disposition_of(part)
    dsp = part.header[:content_disposition]
    return nil unless dsp

    Net::IMAP::ContentDisposition.new(
      dsp.disposition_type.to_s.upcase,
      (dsp.parameters || {}).transform_keys { |key| key.to_s.upcase }
    )
  rescue StandardError
    nil
  end
end
