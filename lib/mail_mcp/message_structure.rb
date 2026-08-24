require "mail"

module MailMCP
  # Flattens an IMAP BODYSTRUCTURE into its leaf parts, each tagged with the
  # RFC 3501 section number needed to FETCH that part on its own. Fetching parts
  # individually is what lets a large message be handled without ever holding the
  # whole thing in memory.
  module MessageStructure
    # Encodings we can fetch and write through in chunks. Quoted-printable cannot be:
    # Mail's decoder normalizes line endings and repairs mis-encoded hard breaks across
    # the whole string, and does not decompose across chunk boundaries.
    STREAMABLE_ENCODINGS = ["base64", "7bit", "8bit", "binary", ""].freeze

    Part = Struct.new(:section, :mime_type, :encoding, :encoded_size, :filename, :charset,
                      keyword_init: true) do
      # Mirrors Mail::Message#attachment?, which keys off a filename being present
      # rather than off the Content-Disposition type.
      def attachment?
        !filename.nil?
      end

      def base64?
        encoding == "base64"
      end

      def streamable?
        STREAMABLE_ENCODINGS.include?(encoding)
      end
    end

    class << self
      def flatten(body, prefix = nil)
        return [] if body.nil?
        return [leaf(body, prefix || "1")] unless body.multipart?

        body.parts.flat_map.with_index(1) do |child, number|
          flatten(child, [prefix, number].compact.join("."))
        end
      end

      private

      def leaf(body, section)
        Part.new(
          section: section,
          mime_type: "#{body.media_type}/#{body.subtype}".downcase,
          encoding: body.encoding.to_s.downcase,
          encoded_size: body.size.to_i,
          filename: param(body.disposition&.param, "filename") || param(body.param, "name"),
          charset: param(body.param, "charset")
        )
      end

      # A parameter can arrive RFC 2231-split across numbered keys (FILENAME*0*,
      # FILENAME*1*) or RFC 2047 encoded. Mail decodes both; a plain key lookup returns
      # nil for the split form, which silently drops the attachment from the response.
      def param(params, name)
        return nil if params.nil? || params.empty?

        value = Mail::ParameterHash[params][name]
        return nil if value.nil?

        # An RFC 2231 extended value is prefixed with charset'language'.
        value = value.sub(/\A[\w-]*'[\w-]*'/, "") if extended?(params, name)
        Mail::Encodings.value_decode(value)
      end

      def extended?(params, name)
        params.any? { |key, _value| key.to_s.downcase.start_with?("#{name}*") }
      end
    end
  end
end
