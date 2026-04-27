require "base64"
require "json"

require_relative "mail_mcp/version"

module MailMCP
end

require_relative "mail_mcp/jwt_service"
require_relative "mail_mcp/pkce"
require_relative "mail_mcp/imap_client"
require_relative "mail_mcp/smtp_client"
require_relative "mail_mcp/attachment_store"
require_relative "mail_mcp/credential_context"
require_relative "mail_mcp/tool"
require_relative "mail_mcp/tools/list_mailboxes_tool"
require_relative "mail_mcp/tools/list_messages_tool"
require_relative "mail_mcp/tools/get_message_tool"
require_relative "mail_mcp/tools/search_messages_tool"
require_relative "mail_mcp/tools/send_email_tool"
require_relative "mail_mcp/tools/save_draft_tool"
require_relative "mail_mcp/tools/delete_message_tool"
require_relative "mail_mcp/tools/move_message_tool"
require_relative "mail_mcp/tools/update_flags_tool"
require_relative "mail_mcp/app"
