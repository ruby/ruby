# frozen_string_literal: true

module Net
  class IMAP < Protocol

    # Decode a string from modified UTF-7 format to UTF-8.
    #
    # UTF-7 is a 7-bit encoding of Unicode [UTF7].  IMAP uses a
    # slightly modified version of this to encode mailbox names
    # containing non-ASCII characters; see [IMAP] section 5.1.3.
    #
    # Net::IMAP does _not_ automatically encode and decode
    # mailbox names to and from UTF-7.
    def self.decode_utf7(s)
      return s.gsub(/&([^-]+)?-/n) {
        if $1
          ($1.tr(",", "/") + "===").unpack1("m").encode(Encoding::UTF_8, Encoding::UTF_16BE)
        else
          "&"
        end
      }
    end

    # Encode a string from UTF-8 format to modified UTF-7.
    def self.encode_utf7(s)
      return s.gsub(/(&)|[^\x20-\x7e]+/) {
        if $1
          "&-"
        else
          base64 = [$&.encode(Encoding::UTF_16BE)].pack("m0")
          "&" + base64.delete("=").tr("/", ",") + "-"
        end
      }.force_encoding("ASCII-8BIT")
    end

    # Formats +time+ as an IMAP-style date.
    def self.format_date(time)
      return time.strftime('%d-%b-%Y')
    end

    # Formats +time+ as an IMAP-style date-time.
    def self.format_datetime(time)
      return time.strftime('%d-%b-%Y %H:%M %z')
    end

  end
end
