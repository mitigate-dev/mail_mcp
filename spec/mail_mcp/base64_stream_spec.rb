require "spec_helper"

RSpec.describe MailMCP::Base64Stream do
  def decode_in_slices(payload, slice_size)
    encoded = [payload].pack("m")
    stream = described_class.new
    out = +""
    encoded.scan(/.{1,#{slice_size}}/m) { |slice| out << stream.push(slice) }
    out << stream.finish
    out
  end

  it "decodes a stream fed in one piece" do
    expect(decode_in_slices("hello world", 4096)).to eq("hello world")
  end

  # The point of the class: chunk boundaries almost never land on a 4-character
  # base64 group, so the remainder has to survive between calls.
  it "decodes identically no matter where the chunks split" do
    payload = (0..255).to_a.pack("C*") * 40

    [1, 2, 3, 5, 7, 16, 64, 1000].each do |slice_size|
      expect(decode_in_slices(payload, slice_size)).to eq(payload), "failed at slice size #{slice_size}"
    end
  end

  it "handles payloads at each padding length" do
    (0..3).each do |extra|
      payload = ("x" * 30) + ("y" * extra)
      expect(decode_in_slices(payload, 5)).to eq(payload)
    end
  end

  it "ignores the line breaks that wrap base64 in real messages" do
    payload = "binary\x00\xFFdata".b * 50
    wrapped = [payload].pack("m") # pack("m") already wraps at 60 characters
    stream = described_class.new
    expect(stream.push(wrapped) + stream.finish).to eq(payload)
  end

  it "returns empty strings rather than nil when it has nothing to emit yet" do
    stream = described_class.new
    expect(stream.push("ab")).to eq("")
    expect(described_class.new.finish).to eq("")
  end

  it "preserves binary encoding" do
    payload = "\x00\x01\xFE\xFF".b * 100
    expect(decode_in_slices(payload, 9).b).to eq(payload)
  end
end
