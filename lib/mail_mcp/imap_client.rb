require "net/imap"

module MailMCP
  class ImapClient
    class AuthError < StandardError; end
    class ConnectionError < StandardError; end

    attr_reader :imap

    def initialize(imap)
      @imap = imap
    end

    def self.validate!(config)
      conn = Net::IMAP.new(config[:host], port: config[:port], ssl: config[:ssl])
      conn.login(config[:username], config[:password])
      conn.logout
      conn.disconnect
    rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => e
      raise AuthError, "IMAP authentication failed: #{e.message}"
    rescue StandardError => e
      raise ConnectionError, "IMAP connection failed: #{e.message}"
    end

    def self.connect(config)
      conn = Net::IMAP.new(config[:host], port: config[:port], ssl: config[:ssl])
      conn.login(config[:username], config[:password])
      client = new(conn)
      yield client
    rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => e
      raise AuthError, "IMAP authentication failed: #{e.message}"
    rescue StandardError => e
      raise ConnectionError, "IMAP connection failed: #{e.message}"
    ensure
      begin
        conn&.logout
      rescue StandardError
        nil
      end
      begin
        conn&.disconnect
      rescue StandardError
        nil
      end
    end

    def list_mailboxes
      @imap.list("", "*").map(&:name)
    end

    def list_messages(folder:, page: 1, per_page: 20)
      @imap.examine(folder)
      uids = @imap.uid_search(["ALL"]).reverse
      total = uids.length
      offset = (page - 1) * per_page
      page_uids = uids[offset, per_page] || []
      return { messages: [], total: total } if page_uids.empty?

      envelopes = @imap.uid_fetch(page_uids, ["ENVELOPE", "FLAGS", "RFC822.SIZE"])
      messages = (envelopes || []).map { |msg| format_envelope(msg) }
      { messages: messages, total: total, page: page, per_page: per_page }
    end

    def get_message(folder:, uid:)
      @imap.examine(folder)
      data = @imap.uid_fetch([uid.to_i], %w[RFC822 FLAGS]).first
      return nil unless data

      raw = data.attr["RFC822"]
      flags = data.attr["FLAGS"]
      parsed = Mail.new(raw)
      attachments = extract_attachments(parsed)
      {
        uid: uid,
        subject: parsed.subject,
        from: parsed.from,
        to: parsed.to,
        cc: parsed.cc,
        date: parsed.date&.iso8601,
        text_body: parsed.text_part&.decoded,
        html_body: parsed.html_part&.decoded,
        flags: flags,
        attachments: attachments
      }
    end

    def search_messages(folder:, query:)
      @imap.examine(folder)
      @imap.search(query.split)
    end

    def delete_message(folder:, uid:)
      @imap.select(folder)
      @imap.uid_store(uid.to_i, "+FLAGS", [:Deleted])
      @imap.expunge
    end

    def move_message(folder:, uid:, destination:)
      @imap.select(folder)
      if @imap.capability.include?("MOVE")
        @imap.uid_move(uid.to_i, destination)
      else
        @imap.uid_copy(uid.to_i, destination)
        @imap.uid_store(uid.to_i, "+FLAGS", [:Deleted])
        @imap.expunge
      end
    end

    def update_flags(folder:, uid:, add: [], remove: [])
      @imap.select(folder)
      @imap.uid_store(uid.to_i, "+FLAGS", add) unless add.empty?
      @imap.uid_store(uid.to_i, "-FLAGS", remove) unless remove.empty?
    end

    def append_message(folder:, raw_message:)
      @imap.append(folder, raw_message, [:Draft], Time.now)
    end

    private

    def format_envelope(msg)
      env = msg.attr["ENVELOPE"]
      {
        uid: msg.attr["UID"],
        subject: env.subject,
        from: format_addresses(env.from),
        to: format_addresses(env.to),
        date: env.date,
        size: msg.attr["RFC822.SIZE"],
        flags: msg.attr["FLAGS"]
      }
    end

    def format_addresses(addrs)
      return [] unless addrs

      addrs.map { |a| "#{a.name} <#{a.mailbox}@#{a.host}>" }
    end

    def extract_attachments(mail)
      mail.attachments.map do |att|
        url = AttachmentStore.upload(
          content: att.decoded,
          filename: att.filename || "attachment",
          content_type: att.content_type
        )
        { filename: att.filename, content_type: att.content_type, size: att.decoded.bytesize, url: url }
      end
    end
  end
end
