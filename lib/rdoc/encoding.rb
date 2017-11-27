# coding: US-ASCII
# frozen_string_literal: true

##
# This class is a wrapper around File IO and Encoding that helps RDoc load
# files and convert them to the correct encoding.

module RDoc::Encoding

  ##
  # Reads the contents of +filename+ and handles any encoding directives in
  # the file.
  #
  # The content will be converted to the +encoding+.  If the file cannot be
  # converted a warning will be printed and nil will be returned.
  #
  # If +force_transcode+ is true the document will be transcoded and any
  # unknown character in the target encoding will be replaced with '?'

  def self.read_file filename, encoding, force_transcode = false
    content = open filename, "rb" do |f| f.read end
    content.gsub!("\r\n", "\n") if RUBY_PLATFORM =~ /mswin|mingw/

    utf8 = content.sub!(/\A\xef\xbb\xbf/, '')

    content = RDoc::Encoding.set_encoding content

    begin
      encoding ||= Encoding.default_external
      orig_encoding = content.encoding

      if not orig_encoding.ascii_compatible? then
        content = content.encode encoding
      elsif utf8 then
        content = RDoc::Encoding.change_encoding content, Encoding::UTF_8
        content = content.encode encoding
      else
        # assume the content is in our output encoding
        content = RDoc::Encoding.change_encoding content, encoding
      end

      unless content.valid_encoding? then
        # revert and try to transcode
        content = RDoc::Encoding.change_encoding content, orig_encoding
        content = content.encode encoding
      end

      unless content.valid_encoding? then
        warn "unable to convert #{filename} to #{encoding}, skipping"
        content = nil
      end
    rescue Encoding::InvalidByteSequenceError,
           Encoding::UndefinedConversionError => e
      if force_transcode then
        content = RDoc::Encoding.change_encoding content, orig_encoding
        content = content.encode(encoding,
                                 :invalid => :replace,
                                 :undef => :replace,
                                 :replace => '?')
        return content
      else
        warn "unable to convert #{e.message} for #{filename}, skipping"
        return nil
      end
    end

    content
  rescue ArgumentError => e
    raise unless e.message =~ /unknown encoding name - (.*)/
    warn "unknown encoding name \"#{$1}\" for #{filename}, skipping"
    nil
  rescue Errno::EISDIR, Errno::ENOENT
    nil
  end

  def self.remove_frozen_string_literal string
    string =~ /\A(?:#!.*\n)?(.*\n)/
    first_line = $1

    if first_line =~ /\A# +frozen[-_]string[-_]literal[=:].+$/i
      string = string.sub first_line, ''
    end

    string
  end

  ##
  # Sets the encoding of +string+ based on the magic comment

  def self.set_encoding string
    string = remove_frozen_string_literal string

    string =~ /\A(?:#!.*\n)?(.*\n)/

    first_line = $1

    name = case first_line
           when /^<\?xml[^?]*encoding=(["'])(.*?)\1/ then $2
           when /\b(?:en)?coding[=:]\s*([^\s;]+)/i   then $1
           else                                           return string
           end

    string = string.sub first_line, ''

    string = remove_frozen_string_literal string

    enc = Encoding.find name
    string = RDoc::Encoding.change_encoding string, enc if enc

    string
  end

  ##
  # Changes encoding based on +encoding+ without converting and returns new
  # string

  def self.change_encoding text, encoding
    if text.kind_of? RDoc::Comment
      text.encode! encoding
    else
      # TODO: Remove this condition after Ruby 2.2 EOL
      if RUBY_VERSION < '2.3.0'
        text.force_encoding encoding
      else
        String.new text, encoding: encoding
      end
    end
  end

end
