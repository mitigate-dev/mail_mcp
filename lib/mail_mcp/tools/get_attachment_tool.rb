module MailMCP
  class GetAttachmentTool < Tool
    tool_name "get_attachment"
    description "Get a pre-signed S3 URL for a previously retrieved attachment"

    input_schema(
      type: "object",
      properties: {
        attachment_id: { type: "string", description: "Attachment ID returned from get_message" }
      },
      required: ["attachment_id"]
    )

    def self.call(attachment_id:, server_context:)
      bucket = ENV.fetch("AWS_S3_BUCKET")
      url = Aws::S3::Presigner.new.presigned_url(:get_object, bucket: bucket, key: attachment_id, expires_in: AttachmentStore::EXPIRY)
      MCP::Tool::Response.new([{ type: "text", text: url }])
    end
  end
end
