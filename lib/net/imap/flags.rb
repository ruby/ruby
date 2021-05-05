# frozen_string_literal: true

module Net
  class IMAP < Protocol

    # :category: Message Flags
    #
    # Flag indicating a message has been seen.
    SEEN = :Seen

    # :category: Message Flags
    #
    # Flag indicating a message has been answered.
    ANSWERED = :Answered

    # :category: Message Flags
    #
    # Flag indicating a message has been flagged for special or urgent
    # attention.
    FLAGGED = :Flagged

    # :category: Message Flags
    #
    # Flag indicating a message has been marked for deletion.  This
    # will occur when the mailbox is closed or expunged.
    DELETED = :Deleted

    # :category: Message Flags
    #
    # Flag indicating a message is only a draft or work-in-progress version.
    DRAFT = :Draft

    # :category: Message Flags
    #
    # Flag indicating that the message is "recent," meaning that this
    # session is the first session in which the client has been notified
    # of this message.
    RECENT = :Recent

    # :category: Mailbox Flags
    #
    # Flag indicating that a mailbox context name cannot contain
    # children.
    NOINFERIORS = :Noinferiors

    # :category: Mailbox Flags
    #
    # Flag indicating that a mailbox is not selected.
    NOSELECT = :Noselect

    # :category: Mailbox Flags
    #
    # Flag indicating that a mailbox has been marked "interesting" by
    # the server; this commonly indicates that the mailbox contains
    # new messages.
    MARKED = :Marked

    # :category: Mailbox Flags
    #
    # Flag indicating that the mailbox does not contains new messages.
    UNMARKED = :Unmarked

    @@max_flag_count = 10000

    # Returns the max number of flags interned to symbols.
    def self.max_flag_count
      return @@max_flag_count
    end

    # Sets the max number of flags interned to symbols.
    def self.max_flag_count=(count)
      @@max_flag_count = count
    end

  end
end
