require "spec_helper"

RSpec.describe MailMCP::App do
  include Rack::Test::Methods

  def app
    described_class
  end

  let(:client_secret) { "test-client-secret-value" }
  let(:client_id) do
    MailMCP::JwtService.issue_client_id(
      imap_host: "imap.example.com", imap_port: 993, imap_ssl: true,
      smtp_host: "smtp.example.com", smtp_port: 587, smtp_ssl: false,
      client_secret: client_secret
    )
  end
  let(:redirect_uri) { "http://localhost:9000/cb" }

  describe "GET /.well-known/oauth-protected-resource" do
    it "returns resource metadata" do
      get "/.well-known/oauth-protected-resource"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["resource"]).to eq(ENV.fetch("BASE_URL", nil))
      expect(body["authorization_servers"]).to include(ENV.fetch("BASE_URL", nil))
    end
  end

  describe "GET /.well-known/oauth-authorization-server" do
    it "returns authorization server metadata without registration_endpoint" do
      get "/.well-known/oauth-authorization-server"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["issuer"]).to eq(ENV.fetch("BASE_URL", nil))
      expect(body["code_challenge_methods_supported"]).to include("S256")
      expect(body).not_to have_key("registration_endpoint")
    end
  end

  describe "GET /oauth/authorize" do
    it "renders the login form showing imap/smtp hosts from client_id JWT" do
      get "/oauth/authorize", {
        client_id: client_id,
        redirect_uri: redirect_uri,
        state: "abc",
        code_challenge: "challenge",
        code_challenge_method: "S256"
      }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("IMAP Username")
      expect(last_response.body).to include("imap.example.com")
      expect(last_response.body).to include("smtp.example.com")
      expect(last_response.body).to include("Connect")
    end

    it "returns 400 for an invalid client_id" do
      get "/oauth/authorize", { client_id: "not-a-jwt", redirect_uri: redirect_uri }
      expect(last_response.status).to eq(400)
    end
  end

  describe "POST /oauth/token" do
    let(:verifier) { SecureRandom.urlsafe_base64(32) }
    let(:challenge) { MailMCP::Pkce.challenge(verifier) }
    let(:creds) do
      {
        "imap_host" => "imap.example.com", "imap_port" => 993, "imap_ssl" => true,
        "imap_username" => "u", "imap_password" => "p",
        "smtp_host" => "smtp.example.com", "smtp_port" => 587, "smtp_ssl" => false,
        "smtp_username" => "u", "smtp_password" => "p"
      }
    end

    def issue_code
      MailMCP::JwtService.issue_code(
        creds: creds,
        code_challenge: challenge,
        redirect_uri: redirect_uri,
        client_id: client_id
      )
    end

    it "issues access_token and refresh_token when code + verifier + client_secret are valid" do
      post "/oauth/token", {
        grant_type: "authorization_code",
        code: issue_code,
        code_verifier: verifier,
        redirect_uri: redirect_uri,
        client_id: client_id,
        client_secret: client_secret
      }
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["access_token"]).not_to be_nil
      expect(body["refresh_token"]).not_to be_nil
      expect(body["token_type"]).to eq("Bearer")
    end

    it "issues a new access_token via refresh_token grant" do
      post "/oauth/token", {
        grant_type: "authorization_code",
        code: issue_code, code_verifier: verifier,
        redirect_uri: redirect_uri, client_id: client_id, client_secret: client_secret
      }
      refresh_token = JSON.parse(last_response.body)["refresh_token"]

      post "/oauth/token", {
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: client_id,
        client_secret: client_secret
      }
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["access_token"]).not_to be_nil
      expect(body["refresh_token"]).not_to be_nil
    end

    it "returns invalid_client for wrong client_secret" do
      post "/oauth/token", {
        grant_type: "authorization_code",
        code: issue_code,
        code_verifier: verifier,
        redirect_uri: redirect_uri,
        client_id: client_id,
        client_secret: "wrong-secret"
      }
      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]).to eq("invalid_client")
    end

    it "returns invalid_client for invalid client_id JWT" do
      post "/oauth/token", {
        grant_type: "authorization_code",
        code: issue_code,
        code_verifier: verifier,
        redirect_uri: redirect_uri,
        client_id: "not-a-jwt",
        client_secret: client_secret
      }
      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]).to eq("invalid_client")
    end

    it "returns invalid_grant for wrong PKCE verifier" do
      post "/oauth/token", {
        grant_type: "authorization_code",
        code: issue_code,
        code_verifier: "wrong-verifier",
        redirect_uri: redirect_uri,
        client_id: client_id,
        client_secret: client_secret
      }
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)["error"]).to eq("invalid_grant")
    end

    it "returns invalid_grant for an invalid code" do
      post "/oauth/token", {
        grant_type: "authorization_code",
        code: "not.a.valid.jwe.token",
        code_verifier: verifier,
        redirect_uri: redirect_uri,
        client_id: client_id,
        client_secret: client_secret
      }
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)["error"]).to eq("invalid_grant")
    end
  end

  describe "POST /mcp" do
    let(:access_token) do
      creds = {
        "imap_host" => "imap.example.com", "imap_port" => 993, "imap_ssl" => true,
        "imap_username" => "u", "imap_password" => "p",
        "smtp_host" => "smtp.example.com", "smtp_port" => 587, "smtp_ssl" => false,
        "smtp_username" => "u", "smtp_password" => "p"
      }
      MailMCP::JwtService.issue(creds)
    end

    let(:mcp_headers) do
      {
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json, text/event-stream",
        "HTTP_AUTHORIZATION" => "Bearer #{access_token}"
      }
    end

    def mcp_request(method, params = {}, id: 1)
      JSON.generate({ jsonrpc: "2.0", id: id, method: method, params: params })
    end

    it "returns the full tool list for tools/list" do
      post "/mcp", mcp_request("tools/list"), mcp_headers

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      tools = body.dig("result", "tools")
      expect(tools).to be_an(Array)
      names = tools.map { |t| t["name"] }
      expect(names).to match_array(%w[
                                     list_mailboxes list_mail_messages get_mail_message search_mail_messages
                                     send_mail_message create_draft_mail_message delete_mail_message
                                     move_mail_message update_mail_message_flags
])
    end

    it "returns 401 for an invalid Bearer token" do
      post "/mcp", mcp_request("tools/list"),
           mcp_headers.merge("HTTP_AUTHORIZATION" => "Bearer invalid.token.here")

      expect(last_response.status).to eq(401)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("invalid_token")
    end
  end

  describe "GET /health" do
    it "returns ok" do
      get "/health"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["status"]).to eq("ok")
    end
  end
end
