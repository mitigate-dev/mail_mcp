require "aws-sdk-s3"
require "securerandom"

module MailMCP
  module AttachmentStore
    EXPIRY = 7 * 24 * 3600

    def self.upload(content:, filename:, content_type:)
      key = "attachments/#{SecureRandom.uuid}/#{filename}"
      bucket = ENV.fetch("AWS_S3_BUCKET")

      s3.put_object(
        bucket: bucket,
        key: key,
        body: content,
        content_type: content_type
      )

      presigner.presigned_url(:get_object, bucket: bucket, key: key, expires_in: EXPIRY)
    end

    def self.s3
      Aws::S3::Client.new
    end
    private_class_method :s3

    def self.presigner
      Aws::S3::Presigner.new(client: s3)
    end
    private_class_method :presigner
  end
end
