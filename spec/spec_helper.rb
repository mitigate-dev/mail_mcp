require_relative "support/simplecov"

require "base64"
require "mail"
require "rack/test"
require "webmock/rspec"

ENV["RACK_ENV"] = "test"
ENV["ENCRYPTION_KEY"] = Base64.strict_encode64(Random.bytes(32))
ENV["BASE_URL"] = "https://mail.mcp.example.com"

require_relative "../lib/mail_mcp"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed
end
