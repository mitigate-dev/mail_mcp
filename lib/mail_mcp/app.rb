require "sinatra/base"
require "sinatra/json"
require "sinatra/multi_route"
require "mcp"
require "uri"

module MailMCP
  class App < Sinatra::Base
    register Sinatra::MultiRoute

    set :views, File.expand_path("../../views", __dir__)
    set :public_folder, false
    set :logging, true

    MCP_TOOLS = [
      ListMailboxesTool,
      ListMailMessagesTool,
      GetMailMessageTool,
      SearchMailMessagesTool,
      SendMailMessageTool,
      CreateDraftMailMessageTool,
      DeleteMailMessageTool,
      MoveMailMessageTool,
      UpdateMailMessageFlagsTool
    ].freeze

    # ── MCP ──────────────────────────────────────────────────────────────────

    route :head, :delete, :get, :options, :patch, :post, :put, "/mcp" do
      server_context, error_response = resolve_mcp_context
      halt(*error_response) if error_response

      mcp_server = MCP::Server.new(
        name: "mail_mcp",
        version: "1.0.0",
        description: "IMAP and SMTP mail server for AI agents",
        tools: MCP_TOOLS,
        server_context: server_context
      )
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(mcp_server, stateless: true)
      status_code, resp_headers, body = transport.call(env)
      halt status_code, resp_headers, body
    end

    # ── OAuth 2.1 Discovery ───────────────────────────────────────────────────

    get "/.well-known/oauth-protected-resource" do
      content_type :json
      JSON.generate({
                      resource: base_url,
                      authorization_servers: [base_url]
                    })
    end

    get "/.well-known/oauth-authorization-server" do
      content_type :json
      JSON.generate({
                      issuer: base_url,
                      authorization_endpoint: "#{base_url}/oauth/authorize",
                      token_endpoint: "#{base_url}/oauth/token",
                      response_types_supported: ["code"],
                      grant_types_supported: ["authorization_code"],
                      code_challenge_methods_supported: ["S256"]
                    })
    end

    # ── Authorization (Login UI) ──────────────────────────────────────────────

    get "/oauth/authorize" do
      client_config = decode_client_id!(params[:client_id])
      return if client_config.nil?

      params[:use_same_credentials] = "1"
      @form = LoginForm.new(params, client_config)
      erb :login
    end

    post "/oauth/authorize" do
      client_config = decode_client_id!(params[:client_id])
      return if client_config.nil?

      @form = LoginForm.new(params, client_config)
      return erb :login unless @form.valid?

      code = JwtService.issue_code(
        creds: @form.creds,
        code_challenge: params[:code_challenge],
        redirect_uri: params[:redirect_uri],
        client_id: params[:client_id]
      )

      redirect_to = URI.parse(params[:redirect_uri])
      query = URI.decode_www_form(redirect_to.query.to_s)
      query << ["code", code]
      query << ["state", params[:state]] if params[:state]
      redirect_to.query = URI.encode_www_form(query)
      redirect redirect_to.to_s
    end

    # ── Token Exchange ────────────────────────────────────────────────────────

    post "/oauth/token" do
      content_type :json

      grant_type    = params[:grant_type]
      client_id     = params[:client_id]
      client_secret = params[:client_secret]

      client_config = begin
        JwtService.decode_client_id(client_id.to_s)
      rescue JwtService::Error
        halt 401, JSON.generate({ error: "invalid_client", error_description: "Invalid client_id" })
      end

      unless client_secret.to_s == client_config["cs"]
        halt 401, JSON.generate({ error: "invalid_client", error_description: "Invalid client_secret" })
      end

      creds = case grant_type
              when "authorization_code"
                exchange_code(params, client_id)
              when "refresh_token"
                exchange_refresh_token(params[:refresh_token])
              else
                halt 400, JSON.generate({ error: "unsupported_grant_type" })
              end

      token_response(creds)
    end

    # ── Health ────────────────────────────────────────────────────────────────

    get "/health" do
      content_type :json
      JSON.generate({ status: "ok" })
    end

    not_found do
      content_type :json
      JSON.generate({ error: "not_found" })
    end

    private

    def resolve_mcp_context
      auth = request.env["HTTP_AUTHORIZATION"]
      return [nil, nil] unless auth&.start_with?("Bearer ")

      creds = JwtService.verify(auth[7..])
      context = CredentialContext.new(
        imap_config: {
          host: creds["imap_host"], port: creds["imap_port"].to_i,
          ssl: creds["imap_ssl"], username: creds["imap_username"], password: creds["imap_password"]
        },
        smtp_config: {
          host: creds["smtp_host"], port: creds["smtp_port"].to_i,
          ssl: creds["smtp_ssl"], username: creds["smtp_username"], password: creds["smtp_password"]
        },
        email: creds["email"],
        full_name: creds["full_name"]
      )
      [context, nil]
    rescue JwtService::Error => e
      error = [
        401,
        { "Content-Type" => "application/json", "WWW-Authenticate" => mcp_www_authenticate },
        [JSON.generate({ error: "invalid_token", error_description: e.message })]
      ]
      [nil, error]
    end

    def exchange_code(params, client_id)
      code          = params[:code]
      code_verifier = params[:code_verifier]
      redirect_uri  = params[:redirect_uri]

      payload = begin
        JwtService.verify_code(code.to_s)
      rescue JwtService::Error => e
        halt 400, JSON.generate({ error: "invalid_grant", error_description: e.message })
      end

      if payload["redirect_uri"] != redirect_uri
        halt 400,
             JSON.generate({ error: "invalid_grant",
                             error_description: "redirect_uri mismatch" })
      end
      halt 400, JSON.generate({ error: "invalid_client" }) if payload["client_id"] != client_id
      unless Pkce.valid?(verifier: code_verifier.to_s, challenge: payload["code_challenge"].to_s)
        halt 400, JSON.generate({ error: "invalid_grant", error_description: "PKCE verification failed" })
      end

      payload.slice(*JwtService::CRED_KEYS)
    end

    def exchange_refresh_token(refresh_token)
      JwtService.verify_refresh(refresh_token.to_s)
    rescue JwtService::Error => e
      halt 400, JSON.generate({ error: "invalid_grant", error_description: e.message })
    end

    def token_response(creds)
      JSON.generate({
                      access_token: JwtService.issue(creds),
                      refresh_token: JwtService.issue_refresh(creds),
                      token_type: "Bearer",
                      expires_in: JwtService::DEFAULT_EXPIRY
                    })
    end

    def mcp_www_authenticate
      "Bearer resource_metadata=\"#{base_url}/.well-known/oauth-protected-resource\""
    end

    def base_url
      ENV.fetch("BASE_URL")
    end

    def decode_client_id!(client_id)
      JwtService.decode_client_id(client_id.to_s)
    rescue JwtService::Error => e
      halt 400, "Invalid client_id: #{e.message}"
      nil
    end
  end
end
