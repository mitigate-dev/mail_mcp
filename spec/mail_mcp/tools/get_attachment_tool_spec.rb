require "spec_helper"

RSpec.describe MailMCP::GetAttachmentTool do
  let(:context) do
    MailMCP::CredentialContext.new(
      imap_config: { host: "imap.example.com", port: 993, ssl: true, username: "user", password: "pass" },
      smtp_config: { host: "smtp.example.com", port: 587, ssl: false, username: "user", password: "pass" }
    )
  end
  let(:presigned_url) { "https://s3.example.com/bucket/attachments/uuid/file.pdf?sig=abc" }
  let(:presigner) { instance_double(Aws::S3::Presigner) }

  before do
    stub_const("ENV", ENV.to_h.merge("AWS_S3_BUCKET" => "test-bucket"))
    allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
    allow(presigner).to receive(:presigned_url).and_return(presigned_url)
  end

  it "returns a presigned S3 URL for the attachment" do
    result = described_class.call(attachment_id: "attachments/uuid/file.pdf", server_context: context).to_h
    expect(result[:content].first[:text]).to eq(presigned_url)
  end

  it "requests the correct S3 key and bucket" do
    described_class.call(attachment_id: "attachments/uuid/file.pdf", server_context: context)
    expect(presigner).to have_received(:presigned_url).with(
      :get_object,
      hash_including(bucket: "test-bucket", key: "attachments/uuid/file.pdf")
    )
  end
end
