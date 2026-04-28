require "base64"
require "json"
require "logger"

require_relative "mail_mcp/version"

module MailMCP
  def self.logger
    @logger ||= Logger.new($stdout, level: ENV.fetch("MAIL_MCP_LOG_LEVEL", "INFO"), progname: "mail_mcp")
  end

  class << self
    attr_writer :logger
  end
end

require_relative "mail_mcp/jwt_service"
require_relative "mail_mcp/pkce"
require_relative "mail_mcp/imap_client"
require_relative "mail_mcp/smtp_client"
require_relative "mail_mcp/attachment_store"
require_relative "mail_mcp/credential_context"
require_relative "mail_mcp/login_form"
require_relative "mail_mcp/mail_builder"
require_relative "mail_mcp/tool"
require_relative "mail_mcp/tools/list_mailboxes_tool"
require_relative "mail_mcp/tools/list_mail_messages_tool"
require_relative "mail_mcp/tools/get_mail_message_tool"
require_relative "mail_mcp/tools/search_mail_messages_tool"
require_relative "mail_mcp/tools/send_mail_message_tool"
require_relative "mail_mcp/tools/create_draft_mail_message_tool"
require_relative "mail_mcp/tools/delete_mail_message_tool"
require_relative "mail_mcp/tools/move_mail_message_tool"
require_relative "mail_mcp/tools/update_mail_message_flags_tool"
require_relative "mail_mcp/app"
