require 'json/common'
require 'json/pure/parser'
require 'json/pure/generator'

module JSON
  begin
    require 'iconv'
    # An iconv instance to convert from UTF8 to UTF16 Big Endian.
    UTF16toUTF8 = Iconv.new('utf-8', 'utf-16be') # :nodoc:
    # An iconv instance to convert from UTF16 Big Endian to UTF8.
    UTF8toUTF16 = Iconv.new('utf-16be', 'utf-8') # :nodoc:
    UTF8toUTF16.iconv('no bom')
  rescue Errno::EINVAL, Iconv::InvalidEncoding
    # Iconv doesn't support big endian utf-16. Let's try to hack this manually
    # into the converters.
    begin
      old_verbose, $VERBSOSE = $VERBOSE, nil
      # An iconv instance to convert from UTF8 to UTF16 Big Endian.
      UTF16toUTF8 = Iconv.new('utf-8', 'utf-16') # :nodoc:
      # An iconv instance to convert from UTF16 Big Endian to UTF8.
      UTF8toUTF16 = Iconv.new('utf-16', 'utf-8') # :nodoc:
      UTF8toUTF16.iconv('no bom')
      if UTF8toUTF16.iconv("\xe2\x82\xac") == "\xac\x20"
        swapper = Class.new do
          def initialize(iconv) # :nodoc:
            @iconv = iconv
          end

          def iconv(string) # :nodoc:
            result = @iconv.iconv(string)
            JSON.swap!(result)
          end
        end
        UTF8toUTF16 = swapper.new(UTF8toUTF16) # :nodoc:
      end
      if UTF16toUTF8.iconv("\xac\x20") == "\xe2\x82\xac"
        swapper = Class.new do
          def initialize(iconv) # :nodoc:
            @iconv = iconv
          end

          def iconv(string) # :nodoc:
            string = JSON.swap!(string.dup)
            @iconv.iconv(string)
          end
        end
        UTF16toUTF8 = swapper.new(UTF16toUTF8) # :nodoc:
      end
    rescue Errno::EINVAL, Iconv::InvalidEncoding
      raise MissingUnicodeSupport, "iconv doesn't seem to support UTF-8/UTF-16 conversions"
    ensure
      $VERBOSE = old_verbose
    end
  rescue LoadError
    raise MissingUnicodeSupport,
      "iconv couldn't be loaded, which is required for UTF-8/UTF-16 conversions"
  end

  # Swap consecutive bytes of _string_ in place.
  def self.swap!(string) # :nodoc:
    0.upto(string.size / 2) do |i|
      break unless string[2 * i + 1]
      string[2 * i], string[2 * i + 1] = string[2 * i + 1], string[2 * i]
    end
    string
  end

  # This module holds all the modules/classes that implement JSON's
  # functionality in pure ruby.
  module Pure
    $DEBUG and warn "Using pure library for JSON."
    JSON.parser = Parser
    JSON.generator = Generator
  end
end
