require "aws-sdk-s3"
require "securerandom"

module MailMCP
  module AttachmentStore
    EXPIRY = 7 * 24 * 3600

    class << self
      # Uploads an in-memory body. Prefer #upload_io for anything attachment-sized:
      # a String body has to be fully resident, which is what we are trying to avoid.
      def upload(content:, filename:, content_type:)
        store(body: content, filename: filename, content_type: content_type)
      end

      # Uploads from an open IO (typically a Tempfile), letting the SDK read it in
      # chunks instead of holding the whole attachment as a String.
      def upload_io(io:, filename:, content_type:)
        io.rewind
        store(body: io, filename: filename, content_type: content_type)
      end

      # Drops the memoized clients. Only needed by tests and after credential changes.
      def reset!
        @s3 = nil
        @presigner = nil
      end

      private

      def store(body:, filename:, content_type:)
        key = "attachments/#{SecureRandom.uuid}/#{filename}"
        bucket = ENV.fetch("AWS_S3_BUCKET")

        s3.put_object(
          bucket: bucket,
          key: key,
          body: body,
          content_type: content_type
        )

        presigner.presigned_url(:get_object, bucket: bucket, key: key, expires_in: EXPIRY)
      end

      # Memoized: building a client cost ~11MB of RSS, and the un-memoized version
      # built two per attachment — once here and once more inside #presigner.
      # Aws::S3::Client is thread-safe, so one instance serves every Puma thread.
      def s3
        @s3 ||= Aws::S3::Client.new
      end

      def presigner
        @presigner ||= Aws::S3::Presigner.new(client: s3)
      end
    end
  end
end
