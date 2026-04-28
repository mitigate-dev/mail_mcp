module MailMCP
  class LoginForm
    attr_reader :errors

    def initialize(params, client_config)
      @params = params
      @client_config = client_config
      @errors = []
    end

    def valid?
      @errors = []
      @errors << "Email: address is required" if email.empty?
      validate_imap
      validate_smtp
      @errors.empty?
    end

    def client_id            = @params[:client_id]
    def redirect_uri         = @params[:redirect_uri]
    def state                = @params[:state]
    def code_challenge       = @params[:code_challenge]
    def code_challenge_method = @params[:code_challenge_method]

    def imap_host = @client_config["imap_host"]
    def smtp_host = @client_config["smtp_host"]

    def imap_username = @params[:imap_username].to_s.strip
    def imap_password = @params[:imap_password].to_s
    def smtp_username = use_same_credentials? ? imap_username : @params[:smtp_username].to_s.strip
    def smtp_password = use_same_credentials? ? imap_password : @params[:smtp_password].to_s
    def email = @params[:email].to_s.strip
    def full_name = @params[:full_name].to_s.strip
    def use_same_credentials? = @params[:use_same_credentials] == "1"

    def imap_config
      { host: imap_host, port: @client_config["imap_port"], ssl: @client_config["imap_ssl"],
        username: imap_username, password: imap_password }
    end

    def smtp_config
      { host: smtp_host, port: @client_config["smtp_port"], ssl: @client_config["smtp_ssl"],
        username: smtp_username, password: smtp_password }
    end

    def creds
      {
        "imap_host" => imap_host, "imap_port" => @client_config["imap_port"],
        "imap_ssl" => @client_config["imap_ssl"],
        "imap_username" => imap_username, "imap_password" => imap_password,
        "smtp_host" => smtp_host, "smtp_port" => @client_config["smtp_port"],
        "smtp_ssl" => @client_config["smtp_ssl"],
        "smtp_username" => smtp_username, "smtp_password" => smtp_password,
        "email" => email, "full_name" => full_name
      }
    end

    private

    def validate_imap
      ImapClient.validate!(imap_config)
    rescue ImapClient::AuthError, ImapClient::ConnectionError => e
      @errors << "IMAP: #{e.message}"
    end

    def validate_smtp
      SmtpClient.validate!(smtp_config)
    rescue SmtpClient::ConnectionError => e
      @errors << "SMTP: #{e.message}"
    end
  end
end
