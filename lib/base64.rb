require "kconv"

#  Perform encoding and decoding of binary data using a Base64
#  representation. This library rather unfortunately loads its four
#  methods directly into the top level namespace.
# 
#      require "base64"
#
#      enc   = encode64('Send reinforcements')
#      puts enc
#      plain = decode64(enc)
#      puts plain


module Base64
  module_function

  # Returns the Base64-decoded version of \obj{str}.
  #
  #   require 'base64'
  #   str = 'VGhpcyBpcyBsaW5lIG9uZQpUaGlzIG' +
  #         'lzIGxpbmUgdHdvClRoaXMgaXMgbGlu' +
  #         'ZSB0aHJlZQpBbmQgc28gb24uLi4K'
  #    puts decode64(str)
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
  # mime-encoding mail headers). Only supports an encoding type of 'b'
  # (base 64), and only supports the character sets ISO-2022-JP and
  # SHIFT_JIS (so the only two encoded word sequences recognized are
  # <tt>=?ISO-2022-JP?B?...=</tt> and
  # <tt>=?SHIFT_JIS?B?...=</tt>). Recognition of these sequences is case
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

  # Returns the Base64-encoded version of \obj{str}.
  #
  #   require 'base64'
  #   str = "Once\nupon\na\ntime."  #!sh!
  #   enc = encode64(str)
  #   decode64(enc)

  def encode64(bin)
    [bin].pack("m")
  end

  # Prints the Base64 encoded version of _bin_ (a +String+) in lines of
  # _len_ (default 60) characters.
  #
  #    require 'base64'
  #    b64encode("Now is the time for all good coders\nto learn Ruby")
  #
  # Generates
  #
  #    Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g
  #    UnVieQ==

  def b64encode(bin, len = 60)
    encode64(bin).scan(/.{1,#{len}}/o) do
      print $&, "\n"
    end
  end 

  module Deprecated
    include Base64

    def _deprecated_base64(*args)
      m0, m1 = caller(0)
      m = m0[/\`(.*?)\'\z/, 1]
      warn("#{m1}: #{m} is deprecated; use Base64.#{m} instead")
      super
    end
    dep = instance_method(:_deprecated_base64)
    remove_method(:_deprecated_base64)
    for m in Base64.private_instance_methods(false)
      define_method(m, dep)
    end
  end
end

include Base64::Deprecated
