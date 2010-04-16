#
# = base64.rb: methods for base64-encoding and -decoding strings
#
# Author:: Yukihiro Matsumoto
# Documentation:: Dave Thomas and Gavin Sinclair
#
# Until Ruby 1.8.1, these methods were defined at the top-level.  Now
# they are in the Base64 module but included in the top-level, where
# their usage is deprecated.
#
# See Base64 for documentation.
#

require "kconv"


# The Base64 module provides for the encoding (#encode64) and decoding
# (#decode64) of binary data using a Base64 representation.
#
# The following particular features are also provided:
# - encode into lines of a given length (#b64encode)
# - decode the special format specified in RFC2047 for the
#   representation of email headers (decode_b)
#
# == Example
#
# A simple encoding and decoding.
#
#     require "base64"
#
#     enc   = Base64.encode64('Send reinforcements')
#                         # -> "U2VuZCByZWluZm9yY2VtZW50cw==\n"
#     plain = Base64.decode64(enc)
#                         # -> "Send reinforcements"
#
# The purpose of using base64 to encode data is that it translates any
# binary data into purely printable characters.  It is specified in
# RFC 2045 (http://www.faqs.org/rfcs/rfc2045.html).

module Base64
  module_function

  # Returns the Base64-decoded version of +str+.
  #
  #   require 'base64'
  #   str = 'VGhpcyBpcyBsaW5lIG9uZQpUaGlzIG' +
  #         'lzIGxpbmUgdHdvClRoaXMgaXMgbGlu' +
  #         'ZSB0aHJlZQpBbmQgc28gb24uLi4K'
  #   puts Base64.decode64(str)
  #
  # <i>Generates:</i>
  #
  #    This is line one
  #    This is line two
  #    This is line three
  #    And so on...

  def decode64(str)
    str.unpack("m")[0]
  end


  # Decodes text formatted using a subset of RFC2047 (the one used for
  # mime-encoding mail headers).
  #
  # Only supports an encoding type of 'b' (base 64), and only supports
  # the character sets ISO-2022-JP and SHIFT_JIS (so the only two
  # encoded word sequences recognized are <tt>=?ISO-2022-JP?B?...=</tt> and
  # <tt>=?SHIFT_JIS?B?...=</tt>).  Recognition of these sequences is case
  # insensitive.

  def decode_b(str)
    str.gsub!(/=\?ISO-2022-JP\?B\?([!->@-~]+)\?=/i) {
      decode64($1)
    }
    str = Kconv::toeuc(str)
    str.gsub!(/=\?SHIFT_JIS\?B\?([!->@-~]+)\?=/i) {
      decode64($1)
    }
    str = Kconv::toeuc(str)
    str.gsub!(/\n/, ' ')
    str.gsub!(/\0/, '')
    str
  end

  # Returns the Base64-encoded version of +str+.
  #
  #    require 'base64'
  #    Base64.b64encode("Now is the time for all good coders\nto learn Ruby")
  #
  # <i>Generates:</i>
  #
  #    Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g
  #    UnVieQ==

  def encode64(bin)
    [bin].pack("m")
  end

  # Returns the Base64-encoded version of +bin+.
  # This method complies with RFC 4648.
  # No line feeds are added.
  def strict_encode64(bin)
    [bin].pack((len = bin.bytesize) > 45 ? "m#{len+2}" : "m").chomp
  end

  # Returns the Base64-decoded version of +str+.
  # This method complies with RFC 4648.
  # ArgumentError is raised if +str+ is incorrectly padded or contains
  # non-alphabet characters.  Note that CR or LF are also rejected.
  def strict_decode64(str)
    return str.unpack("m").first if str.bytesize % 4 == 0 &&
      str.match(%r{\A[A-Za-z0-9+/]*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?\z}) &&
      (!$1 || $1 == $1.unpack('m').pack('m').chomp)
    raise ArgumentError, 'invalid base64'
  end

  # Returns the Base64-encoded version of +bin+.
  # This method complies with ``Base 64 Encoding with URL and Filename Safe
  # Alphabet'' in RFC 4648.
  # The alphabet uses '-' instead of '+' and '_' instead of '/'.
  def urlsafe_encode64(bin)
    strict_encode64(bin).tr("+/", "-_")
  end

  # Returns the Base64-decoded version of +str+.
  # This method complies with ``Base 64 Encoding with URL and Filename Safe
  # Alphabet'' in RFC 4648.
  # The alphabet uses '-' instead of '+' and '_' instead of '/'.
  def urlsafe_decode64(str)
    strict_decode64(str.tr("-_", "+/"))
  end

  # _Prints_ the Base64 encoded version of +bin+ (a +String+) in lines of
  # +len+ (default 60) characters.
  #
  #    require 'base64'
  #    data = "Now is the time for all good coders\nto learn Ruby"
  #    Base64.b64encode(data)
  #
  # <i>Generates:</i>
  #
  #    Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g
  #    UnVieQ==

  def b64encode(bin, len = 60)
    encode64(bin).scan(/.{1,#{len}}/) do
      print $&, "\n"
    end
  end


  module Deprecated # :nodoc:
    include Base64

    for m in Base64.private_instance_methods(false)
      module_eval %{
        def #{m}(*args)
          warn("\#{caller(1)[0]}: #{m} is deprecated; use Base64.#{m} instead")
          super
        end
      }
    end
  end
end

include Base64::Deprecated
