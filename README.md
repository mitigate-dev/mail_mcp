# Mitigate Mail MCP

A hosted [Model Context Protocol](https://modelcontextprotocol.io/) server for IMAP and SMTP email, built in Ruby. It acts as both an OAuth 2.1 Authorization Server and an MCP Resource Server.

## Architecture

```
Client (Claude Desktop / MCP Inspector)
  │
  ├─ OAuth 2.1 flow
  │   GET  /.well-known/oauth-protected-resource   RFC 9728 metadata
  │   GET  /.well-known/oauth-authorization-server  RFC 8414 metadata
  │   GET  /oauth/authorize                         Login UI
  │   POST /oauth/authorize                         Validate IMAP/SMTP → issue code
  │   POST /oauth/token                             Code + PKCE + client_secret → tokens
  │                                                 (also: refresh_token grant)
  │
  └─ MCP calls (all HTTP methods)
      /mcp   Bearer access token → decrypt creds → IMAP/SMTP operations
```

### How authentication works

Clients are provisioned once via the `bin/mail_mcp generate` CLI, which produces:

- **`client_id`** — a JWE token (encrypted, opaque) encoding the IMAP/SMTP server configuration and the `client_secret`. Only the server can decrypt it.
- **`client_secret`** — a random secret used to authenticate the client at the token endpoint.

The OAuth flow:

1. Client redirects the user to `/oauth/authorize?client_id=<jwe>&...`
2. Server decrypts the `client_id` JWE to learn which IMAP/SMTP servers to connect to
3. User enters their IMAP/SMTP username and password in the login form
4. Server validates both connections live; shows an error banner on failure
5. On success: credentials are encrypted directly in a JWE access token and a JWE refresh token
6. Client exchanges the authorization code (`POST /oauth/token`) with `client_id` + `client_secret`; receives `access_token` + `refresh_token`
7. Every MCP request carries `Authorization: Bearer <access_token>`; the server decrypts credentials per-request

### Token formats

All tokens are **5-part JWE** (`dir` / `A256GCM`), encrypted with `ENCRYPTION_KEY`. There is no separate signing key.

| Token | `typ` claim | Expiry | Contents |
|---|---|---|---|
| `client_id` | `client_id` | none | imap/smtp host+port, `client_secret` |
| Access token | `access` | 8 hours | IMAP + SMTP credentials |
| Refresh token | `refresh` | 30 days | IMAP + SMTP credentials |

## Directory Structure

```
mail_mcp/
├── Gemfile
├── .env.sample            # Environment variable template
├── bin/
│   └── mail_mcp           # CLI: `generate` (client_id) and `server` (puma)
├── config.ru              # Rack entry point — run MailMCP::App.new
├── config/
│   └── puma.rb            # Puma config (single worker, 5 threads)
├── lib/
│   ├── mail_mcp.rb        # Module root + requires
│   └── mail_mcp/
│       ├── jwt_service.rb         # All JWE tokens (access, refresh, client_id)
│       ├── pkce.rb                # PKCE S256 challenge/verify
│       ├── credential_context.rb  # Struct passed as MCP server_context per request
│       ├── imap_client.rb         # net-imap wrapper
│       ├── smtp_client.rb         # net-smtp wrapper
│       ├── attachment_store.rb    # S3 upload + presigned URLs (7 days)
│       ├── tool.rb                # MailMCP::Tool base class
│       ├── app.rb                 # Sinatra: OAuth + MCP /mcp route (all methods)
│       └── tools/*.rb             # MCP tool classes
├── views/
│   └── login.erb          # Login form (username + password only)
├── spec/                  # RSpec test suite
└── Dockerfile
```

## Configuration

Copy `.env.sample` to `.env` and fill in the values:

| Variable | Description |
|---|---|
| `BASE_URL` | Public URL of this server, e.g. `https://mail.mcp.mitigate.dev` |
| `ENCRYPTION_KEY` | AES-256 key (base64-encoded 32 bytes) — used for **all** JWE tokens |
| `AWS_ACCESS_KEY_ID` | AWS credentials for S3 attachment storage |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for S3 attachment storage |
| `AWS_REGION` | S3 bucket region, e.g. `us-east-1` |
| `AWS_S3_BUCKET` | S3 bucket name for attachments |
| `PORT` | HTTP port (default `3000`) |
| `RACK_ENV` | `development` or `production` |

Generate `ENCRYPTION_KEY`:
```bash
ruby -e "require 'base64','securerandom'; puts Base64.strict_encode64(SecureRandom.bytes(32))"
```

IMAP/SMTP host and port are embedded in the `client_id` JWE and are never passed as headers or query parameters.

## Setup

```bash
# Install dependencies
bundle install

# Copy and edit environment variables
cp .env.sample .env
$EDITOR .env

# Run tests
bundle exec rspec

# Start the server
bundle exec puma -C config/puma.rb
```

## Provisioning a Client

Run `bin/mail_mcp generate` once per mail server configuration. The resulting `client_id` and `client_secret` are configured in the MCP client (e.g. Claude Desktop).

```bash
bundle exec bin/mail_mcp generate \
  --imap-host=imap.gmail.com \
  --imap-port=993 \
  --smtp-host=smtp.gmail.com \
  --smtp-port=587

#   Client ID:     eyJhbGciOiJkaXIiLCJlbmMiOiJBMjU2R0NNIn0...<encrypted>
#   Client Secret: 713576e2f94802b9d9abfd755e38e29b63e491df...
#
#   IMAP: imap.gmail.com:993 (ssl=true)
#   SMTP: smtp.gmail.com:587 (ssl=false)
```

| Flag | Default | Description |
|---|---|---|
| `--imap-host=HOST` | required | IMAP server hostname |
| `--imap-port=PORT` | `993` | IMAP port |
| `--[no-]imap-ssl` | `true` when port 993 | Enable SSL/TLS for IMAP |
| `--smtp-host=HOST` | required | SMTP server hostname |
| `--smtp-port=PORT` | `587` | SMTP port |
| `--[no-]smtp-ssl` | `true` when port 465 | Enable SSL/TLS for SMTP |

## OAuth 2.1 Flow

1. **Discovery** — client fetches `/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server`
2. **Authorization** — client redirects user to `/oauth/authorize?client_id=<jwe>&code_challenge=<s256>&...`
3. **Login** — server decrypts `client_id` JWE to get IMAP/SMTP hosts; user enters credentials; server validates both connections live
4. **Code exchange** — `POST /oauth/token` with `grant_type=authorization_code`, `code`, `code_verifier`, `client_id`, `client_secret`; server issues `access_token` + `refresh_token`
5. **Token refresh** — `POST /oauth/token` with `grant_type=refresh_token`, `refresh_token`, `client_id`, `client_secret`; server issues a new `access_token` + `refresh_token`
6. **MCP calls** — client sends `Authorization: Bearer <access_token>` on every request; server decrypts credentials per-request via a stateless per-request MCP server

## MCP Tools

| Tool | Parameters | Description |
|---|---|---|
| `list_mailboxes` | — | List all IMAP folders |
| `list_mail_messages` | `folder`, `page`, `per_page` | List messages with pagination |
| `get_mail_message` | `folder`, `uid` | Fetch full message; attachments uploaded to S3 and returned as presigned URLs |
| `search_mail_messages` | `folder`, `query` | Raw IMAP SEARCH criteria, e.g. `UNSEEN` or `FROM alice@example.com SINCE 01-Jan-2025` |
| `send_mail_message` | `to`, `subject`, `body`, `cc`, `bcc`, `html_body`, `attachment_urls`, `folder` | Send via SMTP and append to the Sent folder via IMAP; attachments fetched from S3 presigned URLs |
| `create_draft_mail_message` | `to`, `subject`, `body`, `cc`, `html_body`, `attachment_urls`, `folder` | Append to Drafts via IMAP APPEND; attachments fetched from S3 presigned URLs |
| `delete_mail_message` | `folder`, `uid` | Mark `\Deleted` + EXPUNGE |
| `move_mail_message` | `folder`, `uid`, `destination` | IMAP MOVE (or COPY+DELETE fallback) |
| `update_mail_message_flags` | `folder`, `uid`, `add`, `remove` | Add/remove IMAP flags, e.g. `\Seen`, `\Flagged` |

Attachments are never returned as binary data — they are uploaded to S3 on first access and returned as presigned URLs valid for 7 days.

## Docker

```bash
docker build -t mail_mcp .
docker run -p 3000:3000 --env-file .env mail_mcp
```
