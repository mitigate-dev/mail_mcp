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

    # Consumes +chunk+: it is stripped and sliced in place so that decoding a 4MiB
    # chunk does not allocate three more copies of it. Callers must read anything they
    # need from the chunk (its size, in particular) before calling this.
    def push(chunk)
      chunk = chunk.dup if chunk.frozen?
      chunk.delete!("\r\n\t ")
      chunk.prepend(@carry) unless @carry.empty?
      leftover = chunk.bytesize % GROUP
      @carry = leftover.zero? ? +"" : chunk.slice!(chunk.bytesize - leftover, leftover)
      chunk.empty? ? "".b : chunk.unpack1("m")
    end

    # Decodes whatever is left over, including any padding.
    def finish
      remainder = @carry
      @carry = +""
      remainder.unpack1("m")
    end
  end
end
