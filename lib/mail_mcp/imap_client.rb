require "net/imap"

module MailMCP
  class ImapClient
    class AuthError < StandardError; end
    class ConnectionError < StandardError; end

    OPEN_TIMEOUT = 10
    IDLE_TIMEOUT = 30

    attr_reader :imap

    def initialize(imap)
      @imap = imap
    end

    def self.validate!(config)
      conn = open_connection(config)
      conn.login(config[:username], config[:password])
      conn.logout
      conn.disconnect
    rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => e
      MailMCP.logger.warn { "IMAP authentication failed user=#{config[:username]}: #{e.message}" }
      raise AuthError, "IMAP authentication failed: #{e.message}"
    rescue StandardError => e
      MailMCP.logger.error do
        "IMAP connection failed host=#{config[:host]}:#{config[:port]} ssl=#{config[:ssl]}: #{e.class}: #{e.message}"
      end
      raise ConnectionError, "IMAP connection failed: #{e.message}"
    end

    def self.connect(config)
      conn = open_connection(config)
      conn.login(config[:username], config[:password])
      client = new(conn)
      yield client
    rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => e
      MailMCP.logger.warn { "IMAP authentication failed user=#{config[:username]}: #{e.message}" }
      raise AuthError, "IMAP authentication failed: #{e.message}"
    rescue StandardError => e
      MailMCP.logger.error do
        "IMAP connection failed host=#{config[:host]}:#{config[:port]} ssl=#{config[:ssl]}: #{e.class}: #{e.message}"
      end
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
      MailMCP.logger.info { "IMAP list_mailboxes" }
      @imap.list("", "*").map(&:name)
    end

    def list_messages(folder:, page: 1, per_page: 20)
      MailMCP.logger.info { "IMAP list_messages folder=#{folder.inspect} page=#{page} per_page=#{per_page}" }
      @imap.examine(folder)
      uids = @imap.uid_search(["ALL"]).reverse
      total = uids.length
      offset = (page - 1) * per_page
      page_uids = uids[offset, per_page] || []
      MailMCP.logger.debug { "IMAP list_messages folder=#{folder.inspect} total=#{total} returned=#{page_uids.size}" }
      return { messages: [], total: total } if page_uids.empty?

      envelopes = @imap.uid_fetch(page_uids, ["ENVELOPE", "FLAGS", "RFC822.SIZE"])
      messages = (envelopes || []).map { |msg| format_envelope(msg) }
      { messages: messages, total: total, page: page, per_page: per_page }
    end

    def get_message(folder:, uid:)
      MailMCP.logger.info { "IMAP get_message folder=#{folder.inspect} uid=#{uid}" }
      @imap.examine(folder)
      data = @imap.uid_fetch([uid.to_i], %w[RFC822 FLAGS]).first
      unless data
        MailMCP.logger.warn { "IMAP get_message not found folder=#{folder.inspect} uid=#{uid}" }
        return nil
      end

      format_message(uid: uid, parsed: Mail.new(data.attr["RFC822"]), flags: data.attr["FLAGS"])
    end

    def search_messages(folder:, query:)
      MailMCP.logger.info { "IMAP search_messages folder=#{folder.inspect} query=#{query.inspect}" }
      @imap.examine(folder)
      results = @imap.search(query.split)
      MailMCP.logger.debug { "IMAP search_messages matched=#{results.size}" }
      results
    end

    def delete_message(folder:, uid:)
      MailMCP.logger.info { "IMAP delete_message folder=#{folder.inspect} uid=#{uid}" }
      @imap.select(folder)
      @imap.uid_store(uid.to_i, "+FLAGS", [:Deleted])
      @imap.expunge
    end

    def move_message(folder:, uid:, destination:)
      MailMCP.logger.info { "IMAP move_message folder=#{folder.inspect} uid=#{uid} destination=#{destination.inspect}" }
      @imap.select(folder)
      if @imap.capability.include?("MOVE")
        @imap.uid_move(uid.to_i, destination)
      else
        MailMCP.logger.debug { "IMAP move_message falling back to copy+delete (server lacks MOVE)" }
        @imap.uid_copy(uid.to_i, destination)
        @imap.uid_store(uid.to_i, "+FLAGS", [:Deleted])
        @imap.expunge
      end
    end

    def update_flags(folder:, uid:, add: [], remove: [])
      MailMCP.logger.info do
        "IMAP update_flags folder=#{folder.inspect} uid=#{uid} add=#{add.inspect} remove=#{remove.inspect}"
      end
      @imap.select(folder)
      @imap.uid_store(uid.to_i, "+FLAGS", add) unless add.empty?
      @imap.uid_store(uid.to_i, "-FLAGS", remove) unless remove.empty?
    end

    def append_message(folder:, raw_message:, flags: [:Seen])
      MailMCP.logger.info do
        "IMAP append_message folder=#{folder.inspect} flags=#{flags.inspect} bytes=#{raw_message.bytesize}"
      end
      @imap.append(folder, raw_message, flags, Time.now)
    end

    def self.open_connection(config)
      MailMCP.logger.debug do
        "IMAP connect host=#{config[:host]} port=#{config[:port]} ssl=#{config[:ssl]} user=#{config[:username]}"
      end
      Net::IMAP.new(config[:host], port: config[:port], ssl: config[:ssl], open_timeout: OPEN_TIMEOUT,
                                   idle_response_timeout: IDLE_TIMEOUT)
    end
    private_class_method :open_connection

    private

    def format_message(uid:, parsed:, flags:)
      {
        uid: uid,
        message_id: parsed.message_id,
        in_reply_to: parsed.in_reply_to,
        references: parsed.references,
        subject: parsed.subject,
        from: parsed.from,
        sender: parsed.sender,
        reply_to: parsed.reply_to,
        to: parsed.to,
        cc: parsed.cc,
        bcc: parsed.bcc,
        date: parsed.date&.iso8601,
        text_body: parsed.text_part&.decoded,
        html_body: parsed.html_part&.decoded,
        flags: flags,
        attachments: extract_attachments(parsed)
      }
    end

    def format_envelope(msg)
      env = msg.attr["ENVELOPE"]
      {
        uid: msg.attr["UID"],
        message_id: env.message_id,
        in_reply_to: env.in_reply_to,
        subject: env.subject,
        from: format_addresses(env.from),
        sender: format_addresses(env.sender),
        reply_to: format_addresses(env.reply_to),
        to: format_addresses(env.to),
        cc: format_addresses(env.cc),
        bcc: format_addresses(env.bcc),
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
