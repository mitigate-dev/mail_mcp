require "json/jwt"

module MailMCP
  module JwtService
    class Error < StandardError; end

    DEFAULT_EXPIRY         = 8 * 3600
    DEFAULT_REFRESH_EXPIRY = 30 * 24 * 3600

    CRED_KEYS = %w[
      imap_host imap_port imap_ssl imap_username imap_password
      smtp_host smtp_port smtp_ssl smtp_username smtp_password
      email full_name
    ].freeze

    # Access token — JWE (dir/A256GCM), credentials embedded directly in payload
    def self.issue(creds, expires_in: DEFAULT_EXPIRY)
      issue_jwe(creds.merge("typ" => "access"), expires_in: expires_in)
    end

    def self.verify(token)
      payload = decode_jwe(token)
      raise Error, "Not an access token" unless payload["typ"] == "access"

      payload.slice(*CRED_KEYS)
    end

    # Refresh token — JWE, longer-lived, carries same credential payload
    def self.issue_refresh(creds, expires_in: DEFAULT_REFRESH_EXPIRY)
      issue_jwe(creds.merge("typ" => "refresh"), expires_in: expires_in)
    end

    def self.verify_refresh(token)
      payload = decode_jwe(token)
      raise Error, "Not a refresh token" unless payload["typ"] == "refresh"

      payload.slice(*CRED_KEYS)
    end

    # Authorization code — short-lived JWE carrying creds + PKCE state (stateless PKCE)
    CODE_EXPIRY = 300 # 5 minutes

    def self.issue_code(creds:, code_challenge:, redirect_uri:, client_id:)
      issue_jwe(
        creds.merge(
          "typ" => "code",
          "code_challenge" => code_challenge,
          "redirect_uri" => redirect_uri,
          "client_id" => client_id
        ),
        expires_in: CODE_EXPIRY
      )
    end

    def self.verify_code(token)
      payload = decode_jwe(token)
      raise Error, "Not an authorization code" unless payload["typ"] == "code"

      payload
    end

    # Client ID token — JWE, no expiry, carries imap/smtp config + client_secret
    def self.issue_client_id(imap_host:, imap_port:, imap_ssl:, smtp_host:, smtp_port:, smtp_ssl:, client_secret:)
      payload = JSON.generate(
        iss: ENV.fetch("BASE_URL"),
        aud: ENV.fetch("BASE_URL"),
        typ: "client_id",
        imap_host: imap_host,
        imap_port: imap_port.to_i,
        imap_ssl: imap_ssl,
        smtp_host: smtp_host,
        smtp_port: smtp_port.to_i,
        smtp_ssl: smtp_ssl,
        cs: client_secret
      )
      encrypt_jwe(payload)
    end

    def self.decode_client_id(token)
      payload = decode_jwe(token, verify_exp: false)
      raise Error, "Not a client_id token" unless payload["typ"] == "client_id"

      payload
    end

    def self.issue_jwe(payload_hash, expires_in:)
      now = Time.now.to_i
      payload = JSON.generate(
        payload_hash.merge(
          "iss" => ENV.fetch("BASE_URL"),
          "aud" => ENV.fetch("BASE_URL"),
          "iat" => now,
          "exp" => now + expires_in
        )
      )
      encrypt_jwe(payload)
    end
    private_class_method :issue_jwe

    def self.encrypt_jwe(payload_json)
      jwe = JSON::JWE.new(payload_json)
      jwe.alg = :dir
      jwe.enc = :A256GCM
      jwe.encrypt!(encryption_key)
      jwe.to_s
    end
    private_class_method :encrypt_jwe

    def self.decode_jwe(token, verify_exp: true)
      jwe = JSON::JWE.decode(token, encryption_key)
      payload = JSON.parse(jwe.plain_text)
      raise Error, "Token expired"    if verify_exp && payload["exp"].to_i < Time.now.to_i
      raise Error, "Invalid issuer"   if payload["iss"] != ENV.fetch("BASE_URL")
      raise Error, "Invalid audience" if payload["aud"] != ENV.fetch("BASE_URL")

      payload
    rescue JSON::JWT::Exception => e
      raise Error, e.message
    end
    private_class_method :decode_jwe

    def self.encryption_key
      Base64.strict_decode64(ENV.fetch("ENCRYPTION_KEY"))
    end
    private_class_method :encryption_key
  end
end
