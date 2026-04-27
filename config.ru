if ENV["RACK_ENV"] != "production"
  require "dotenv"
  Dotenv.load
end

require_relative "lib/mail_mcp"

run MailMCP::App.new
