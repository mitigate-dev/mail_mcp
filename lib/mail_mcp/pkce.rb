require "digest"
require "securerandom"

module MailMCP
  module Pkce
    def self.challenge(verifier)
      Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    end

    def self.valid?(verifier:, challenge:)
      expected = challenge(verifier)
      begin
        ActiveSupport::SecurityUtils.secure_compare(expected, challenge)
      rescue StandardError
        (expected == challenge)
      end
    end
  end
end
