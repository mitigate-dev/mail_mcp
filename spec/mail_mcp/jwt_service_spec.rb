require "spec_helper"

RSpec.describe MailMCP::JwtService do
  let(:creds) do
    {
      "imap_host" => "imap.example.com", "imap_port" => 993,
      "imap_ssl" => true, "imap_username" => "user", "imap_password" => "pass",
      "smtp_host" => "smtp.example.com", "smtp_port" => 587,
      "smtp_ssl" => false, "smtp_username" => "user", "smtp_password" => "pass"
    }
  end

  describe ".issue / .verify (access tokens)" do
    it "produces a 5-part JWE token" do
      expect(described_class.issue(creds).split(".").length).to eq(5)
    end

    it "round-trips all credential fields" do
      token = described_class.issue(creds)
      expect(described_class.verify(token)).to eq(creds)
    end

    it "raises Error on an invalid token" do
      expect { described_class.verify("bad.token.x.y.z") }
        .to raise_error(described_class::Error)
    end

    it "raises Error on an expired token" do
      token = described_class.issue(creds, expires_in: -1)
      expect { described_class.verify(token) }.to raise_error(described_class::Error, /expired/i)
    end

    it "raises Error when token type is not access" do
      refresh = described_class.issue_refresh(creds)
      expect { described_class.verify(refresh) }.to raise_error(described_class::Error)
    end
  end

  describe ".issue_refresh / .verify_refresh (refresh tokens)" do
    it "produces a 5-part JWE token" do
      expect(described_class.issue_refresh(creds).split(".").length).to eq(5)
    end

    it "round-trips all credential fields" do
      token = described_class.issue_refresh(creds)
      expect(described_class.verify_refresh(token)).to eq(creds)
    end

    it "raises Error on an expired refresh token" do
      token = described_class.issue_refresh(creds, expires_in: -1)
      expect { described_class.verify_refresh(token) }.to raise_error(described_class::Error, /expired/i)
    end

    it "raises Error when token type is not refresh" do
      access = described_class.issue(creds)
      expect { described_class.verify_refresh(access) }.to raise_error(described_class::Error)
    end
  end

  describe ".issue_code / .verify_code (authorization codes)" do
    let(:code_params) do
      {
        creds: creds,
        code_challenge: "S256_challenge_value",
        redirect_uri: "http://localhost:9000/cb",
        client_id: "some-client-id"
      }
    end

    it "produces a 5-part JWE token" do
      expect(described_class.issue_code(**code_params).split(".").length).to eq(5)
    end

    it "round-trips creds and OAuth state" do
      token = described_class.issue_code(**code_params)
      payload = described_class.verify_code(token)
      expect(payload["code_challenge"]).to eq("S256_challenge_value")
      expect(payload["redirect_uri"]).to eq("http://localhost:9000/cb")
      expect(payload["client_id"]).to eq("some-client-id")
      expect(payload["imap_host"]).to eq("imap.example.com")
    end

    it "expires after CODE_EXPIRY seconds" do
      token = described_class.issue_code(**code_params, creds: creds)
      # Verify works when not expired
      expect { described_class.verify_code(token) }.not_to raise_error
    end

    it "raises Error on an expired code" do
      allow(Time).to receive(:now).and_return(Time.now - described_class::CODE_EXPIRY - 1)
      token = described_class.issue_code(**code_params)
      allow(Time).to receive(:now).and_call_original
      expect { described_class.verify_code(token) }.to raise_error(described_class::Error, /expired/i)
    end

    it "raises Error when token type is not code" do
      access = described_class.issue(creds)
      expect { described_class.verify_code(access) }.to raise_error(described_class::Error)
    end

    it "raises Error for tampered token" do
      expect { described_class.verify_code("bad.token.x.y.z") }.to raise_error(described_class::Error)
    end
  end

  describe ".issue_client_id / .decode_client_id" do
    let(:client_secret) { "my-secret-value" }
    let(:client_id_token) do
      described_class.issue_client_id(
        imap_host: "imap.example.com", imap_port: 993, imap_ssl: true,
        smtp_host: "smtp.example.com", smtp_port: 587, smtp_ssl: false,
        client_secret: client_secret
      )
    end

    it "produces a 5-part JWE token (opaque to clients)" do
      expect(client_id_token.split(".").length).to eq(5)
    end

    it "embeds imap config in the token" do
      payload = described_class.decode_client_id(client_id_token)
      expect(payload["imap_host"]).to eq("imap.example.com")
      expect(payload["imap_port"]).to eq(993)
    end

    it "embeds smtp config in the token" do
      payload = described_class.decode_client_id(client_id_token)
      expect(payload["smtp_host"]).to eq("smtp.example.com")
      expect(payload["smtp_port"]).to eq(587)
    end

    it "embeds client_secret in the token" do
      payload = described_class.decode_client_id(client_id_token)
      expect(payload["cs"]).to eq(client_secret)
    end

    it "does not expire" do
      payload = described_class.decode_client_id(client_id_token)
      expect(payload["exp"]).to be_nil
    end

    it "raises Error for tampered/invalid JWE" do
      expect { described_class.decode_client_id("bad.token.x.y.z") }
        .to raise_error(described_class::Error)
    end

    it "raises Error when given an access token instead" do
      access = described_class.issue(creds)
      expect { described_class.decode_client_id(access) }.to raise_error(described_class::Error)
    end
  end
end
