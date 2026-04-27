require_relative "lib/mail_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "mail_mcp"
  spec.version = MailMCP::VERSION
  spec.authors = ["Edgars Beigarts"]
  spec.email = ["edgars.beigarts@mitigate.dev"]

  spec.summary = "Hosted MCP server for IMAP and SMTP email."
  spec.description = "A Model Context Protocol server providing IMAP/SMTP email tools " \
                     "behind an OAuth 2.1 authorization server."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "views/**/*", "config.ru", "config/**/*", "bin/*", "README.md"]
  spec.bindir = "bin"
  spec.executables = ["generate-client"]
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-s3", "~> 1.0"
  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "json-jwt", "~> 1.16"
  spec.add_dependency "mail", "~> 2.8"
  spec.add_dependency "mcp", "~> 0.14"
  spec.add_dependency "puma", "~> 6.0"
  spec.add_dependency "rack", "~> 3.0"
  spec.add_dependency "securerandom"
  spec.add_dependency "sinatra", "~> 4.0"
  spec.add_dependency "sinatra-contrib", "~> 4.0"
end
