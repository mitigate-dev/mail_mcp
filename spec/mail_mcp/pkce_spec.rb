require "spec_helper"

RSpec.describe MailMCP::Pkce do
  describe ".challenge" do
    let(:challenge) { described_class.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") }

    it "produces a URL-safe base64 string" do
      expect(challenge).to match(/\A[A-Za-z0-9\-_]+\z/)
    end

    it "omits padding characters" do
      expect(challenge).not_to include("=")
    end
  end

  describe ".valid?" do
    it "returns true when verifier matches challenge" do
      verifier = SecureRandom.urlsafe_base64(32)
      challenge = described_class.challenge(verifier)
      expect(described_class.valid?(verifier: verifier, challenge: challenge)).to be true
    end

    it "returns false for wrong verifier" do
      verifier = SecureRandom.urlsafe_base64(32)
      challenge = described_class.challenge(verifier)
      expect(described_class.valid?(verifier: "wrong", challenge: challenge)).to be false
    end
  end
end
