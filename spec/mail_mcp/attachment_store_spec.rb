require "spec_helper"

RSpec.describe MailMCP::AttachmentStore do
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:presigner) { instance_double(Aws::S3::Presigner) }
  let(:presigned_url) { "https://s3.example.com/bucket/attachments/uuid/file.pdf?X-Amz-Signature=abc" }

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
    allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
    allow(s3_client).to receive(:put_object)
    allow(presigner).to receive(:presigned_url).and_return(presigned_url)
    stub_const("ENV", ENV.to_h.merge("AWS_S3_BUCKET" => "test-bucket"))
    # The client and presigner are memoized to avoid rebuilding them per attachment.
    described_class.reset!
  end

  describe ".upload" do
    it "uploads to S3 and returns a presigned URL" do
      url = described_class.upload(
        content: "PDF content",
        filename: "report.pdf",
        content_type: "application/pdf"
      )
      expect(s3_client).to have_received(:put_object).with(
        hash_including(bucket: "test-bucket", content_type: "application/pdf")
      )
      expect(url).to eq(presigned_url)
    end

    it "reuses one memoized client and presigner across uploads" do
      2.times { described_class.upload(content: "d", filename: "f.txt", content_type: "text/plain") }
      expect(Aws::S3::Client).to have_received(:new).once
      expect(Aws::S3::Presigner).to have_received(:new).once
    end

    it "generates a unique S3 key for each upload" do
      keys = 2.times.map do
        key = nil
        allow(s3_client).to receive(:put_object) { |args| key = args[:key] }
        described_class.upload(content: "data", filename: "file.txt", content_type: "text/plain")
        key
      end
      expect(keys.first).not_to eq(keys.last)
    end
  end

  describe ".upload_io" do
    it "streams the IO to S3 as the request body" do
      io = StringIO.new("streamed bytes")
      url = described_class.upload_io(io: io, filename: "big.bin", content_type: "application/octet-stream")

      expect(s3_client).to have_received(:put_object).with(hash_including(body: io))
      expect(url).to eq(presigned_url)
    end

    it "rewinds the IO so a partially read tempfile still uploads in full" do
      io = StringIO.new("streamed bytes")
      io.read(4)
      described_class.upload_io(io: io, filename: "big.bin", content_type: "application/octet-stream")
      expect(io.pos).to eq(0)
    end
  end
end
