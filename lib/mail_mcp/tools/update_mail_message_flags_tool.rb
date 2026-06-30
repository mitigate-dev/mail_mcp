module MailMCP
  class UpdateMailMessageFlagsTool < Tool
    tool_name "update_mail_message_flags"
    description "Update IMAP flags on a message (mark as read, flagged, etc.)"
    annotations(
      title: "Update Mail Message Flags",
      read_only_hint: false,
      destructive_hint: true,
      idempotent_hint: false,
      open_world_hint: true
    )

    # IMAP allows only these six backslash-prefixed system flags; anything else
    # must be sent as a keyword (a bare atom with no leading backslash).
    SYSTEM_FLAGS = %w[Seen Answered Flagged Deleted Draft Recent].freeze

    # Friendly color names map to Mozilla/Thunderbird $labelN keywords, the
    # de-facto cross-client convention for colored flags.
    COLOR_KEYWORDS = {
      "red" => "$label1",
      "orange" => "$label2",
      "green" => "$label3",
      "blue" => "$label4",
      "purple" => "$label5"
    }.freeze

    input_schema(
      type: "object",
      properties: {
        folder: { type: "string" },
        uid: { type: "integer" },
        add: { type: "array", items: { type: "string" },
               description: "Flags to add. Settable system flags: '\\\\Seen', '\\\\Answered', " \
                            "'\\\\Flagged', '\\\\Deleted', '\\\\Draft' (\\\\Recent is recognized " \
                            "but cannot be set by clients). Color names " \
                            "('red', 'orange', 'green', 'blue', 'purple') map to " \
                            "$labelN keywords. Any other value is sent as a custom keyword." },
        remove: { type: "array", items: { type: "string" }, description: "Flags to remove" }
      },
      required: %w[folder uid]
    )

    def self.call(folder:, uid:, server_context:, add: [], remove: [])
      add_flags    = add.map { |f| normalize_flag(f) }
      remove_flags = remove.map { |f| normalize_flag(f) }
      ImapClient.connect(server_context.imap_config) do |c|
        c.update_flags(folder: folder, uid: uid, add: add_flags, remove: remove_flags)
      end
      MCP::Tool::Response.new([{ type: "text", text: "Flags updated for message #{uid}" }])
    end

    # System flags become Symbols (net/imap renders them with a leading
    # backslash). Custom keywords stay Strings (rendered as bare atoms).
    # Friendly color names are translated to their $labelN keyword first.
    def self.normalize_flag(flag)
      name = flag.to_s.delete_prefix("\\")
      return COLOR_KEYWORDS.fetch(name.downcase) if COLOR_KEYWORDS.key?(name.downcase)

      # System flags are case-insensitive per RFC 3501; normalize to the
      # canonical capitalization so e.g. "seen" / "\\SEEN" still set :Seen.
      system_flag = SYSTEM_FLAGS.find { |f| f.casecmp?(name) }
      system_flag ? system_flag.to_sym : name
    end
  end
end
