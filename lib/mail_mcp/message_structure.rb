require "net/imap"

module MailMCP
  # Flattens an IMAP BODYSTRUCTURE into its leaf parts, each tagged with the
  # RFC 3501 section number needed to FETCH that part on its own. Fetching parts
  # individually is what lets a large message be handled without ever holding the
  # whole thing in memory.
  module MessageStructure
    IDENTITY_ENCODINGS = ["7bit", "8bit", "binary", ""].freeze

    Part = Struct.new(:section, :media_type, :subtype, :encoding, :encoded_size, :filename,
                      :charset, :content_id, keyword_init: true) do
      def mime_type
        "#{media_type}/#{subtype}"
      end

      # Mirrors Mail::Message#attachment?, which keys off a filename being present
      # rather than off the Content-Disposition type.
      def attachment?
        !filename.nil?
      end

      def base64?
        encoding == "base64"
      end

      # Encodings we can fetch and write through in chunks. Anything else (in
      # practice quoted-printable) has to be decoded in one pass.
      def streamable?
        encoded_size.positive? && (base64? || IDENTITY_ENCODINGS.include?(encoding))
      end
    end

    class << self
      def flatten(body, prefix = nil)
        return [] if body.nil?

        if body.multipart?
          body.parts.each_with_index.flat_map do |child, index|
            flatten(child, [prefix, index + 1].compact.join("."))
          end
        else
          [leaf(body, prefix || "1")]
        end
      end

      private

      def leaf(body, section)
        Part.new(
          section: section,
          media_type: body.media_type.to_s.downcase,
          subtype: body.subtype.to_s.downcase,
          encoding: body.encoding.to_s.downcase,
          encoded_size: body.size.to_i,
          filename: filename_for(body),
          charset: param(body.param, "charset"),
          content_id: body.content_id
        )
      end

      def filename_for(body)
        param(body.disposition&.param, "filename") || param(body.param, "name")
      end

      # Servers pick their own case for parameter names, so never index directly.
      def param(params, name)
        return nil unless params

        pair = params.find { |key, _value| key.to_s.casecmp?(name) }
        pair&.last
      end
    end
  end
end
