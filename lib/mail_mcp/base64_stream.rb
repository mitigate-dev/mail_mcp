module MailMCP
  # Incremental base64 decoder. Feed it arbitrary slices of a base64 stream and it
  # emits decoded bytes as soon as it holds complete four-character groups, carrying
  # the remainder (always fewer than four characters) into the next call. This is what
  # lets an attachment of any size be decoded with a bounded amount of memory.
  class Base64Stream
    GROUP = 4

    def initialize
      @carry = +""
    end

    def push(chunk)
      buffer = @carry + chunk.delete("\r\n\t ")
      complete = buffer.bytesize - (buffer.bytesize % GROUP)
      @carry = buffer.byteslice(complete, buffer.bytesize - complete) || +""
      return "".b if complete.zero?

      buffer.byteslice(0, complete).unpack1("m")
    end

    # Decodes whatever is left over, including any padding.
    def finish
      return "".b if @carry.empty?

      remainder = @carry
      @carry = +""
      remainder.unpack1("m")
    end
  end
end
