# -*- coding: us-ascii -*-
# frozen_string_literal: true

# == \Random number formatter.
#
# Formats generated random numbers in many manners. When <tt>'random/formatter'</tt>
# is required, several methods are added to empty core module <tt>Random::Formatter</tt>,
# making them available as Random's instance and module methods.
#
# Standard library SecureRandom is also extended with the module, and the methods
# described below are available as a module methods in it.
#
# === Examples
#
# Generate random hexadecimal strings:
#
#   require 'random/formatter'
#
#   prng = Random.new
#   prng.hex(10) #=> "52750b30ffbc7de3b362"
#   prng.hex(10) #=> "92b15d6c8dc4beb5f559"
#   prng.hex(13) #=> "39b290146bea6ce975c37cfc23"
#   # or just
#   Random.hex #=> "1aed0c631e41be7f77365415541052ee"
#
# Generate random base64 strings:
#
#   prng.base64(10) #=> "EcmTPZwWRAozdA=="
#   prng.base64(10) #=> "KO1nIU+p9DKxGg=="
#   prng.base64(12) #=> "7kJSM/MzBJI+75j8"
#   Random.base64(4) #=> "bsQ3fQ=="
#
# Generate random binary strings:
#
#   prng.random_bytes(10) #=> "\016\t{\370g\310pbr\301"
#   prng.random_bytes(10) #=> "\323U\030TO\234\357\020\a\337"
#   Random.random_bytes(6) #=> "\xA1\xE6Lr\xC43"
#
# Generate alphanumeric strings:
#
#   prng.alphanumeric(10) #=> "S8baxMJnPl"
#   prng.alphanumeric(10) #=> "aOxAg8BAJe"
#   Random.alphanumeric #=> "TmP9OsJHJLtaZYhP"
#
# Generate UUIDs:
#
#   prng.uuid #=> "2d931510-d99f-494a-8c67-87feb05e1594"
#   prng.uuid #=> "bad85eb9-0713-4da7-8d36-07a8e4b00eab"
#   Random.uuid #=> "f14e0271-de96-45cc-8911-8910292a42cd"
#
# All methods are available in the standard library SecureRandom, too:
#
#   SecureRandom.hex #=> "05b45376a30c67238eb93b16499e50cf"

module Random::Formatter

  # Generate a random binary string.
  #
  # The argument _n_ specifies the length of the result string.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in future.
  #
  # The result may contain any byte: "\x00" - "\xff".
  #
  #   require 'random/formatter'
  #
  #   Random.random_bytes #=> "\xD8\\\xE0\xF4\r\xB2\xFC*WM\xFF\x83\x18\xF45\xB6"
  #   # or
  #   prng = Random.new
  #   prng.random_bytes #=> "m\xDC\xFC/\a\x00Uf\xB2\xB2P\xBD\xFF6S\x97"
  def random_bytes(n=nil)
    n = n ? n.to_int : 16
    gen_random(n)
  end

  # Generate a random hexadecimal string.
  #
  # The argument _n_ specifies the length, in bytes, of the random number to be generated.
  # The length of the resulting hexadecimal string is twice of _n_.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The result may contain 0-9 and a-f.
  #
  #   require 'random/formatter'
  #
  #   Random.hex #=> "eb693ec8252cd630102fd0d0fb7c3485"
  #   # or
  #   prng = Random.new
  #   prng.hex #=> "91dc3bfb4de5b11d029d376634589b61"
  def hex(n=nil)
    random_bytes(n).unpack1("H*")
  end

  # Generate a random base64 string.
  #
  # The argument _n_ specifies the length, in bytes, of the random number
  # to be generated. The length of the result string is about 4/3 of _n_.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The result may contain A-Z, a-z, 0-9, "+", "/" and "=".
  #
  #   require 'random/formatter'
  #
  #   Random.base64 #=> "/2BuBuLf3+WfSKyQbRcc/A=="
  #   # or
  #   prng = Random.new
  #   prng.base64 #=> "6BbW0pxO0YENxn38HMUbcQ=="
  #
  # See RFC 3548 for the definition of base64.
  def base64(n=nil)
    [random_bytes(n)].pack("m0")
  end

  # Generate a random URL-safe base64 string.
  #
  # The argument _n_ specifies the length, in bytes, of the random number
  # to be generated. The length of the result string is about 4/3 of _n_.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The boolean argument _padding_ specifies the padding.
  # If it is false or nil, padding is not generated.
  # Otherwise padding is generated.
  # By default, padding is not generated because "=" may be used as a URL delimiter.
  #
  # The result may contain A-Z, a-z, 0-9, "-" and "_".
  # "=" is also used if _padding_ is true.
  #
  #   require 'random/formatter'
  #
  #   Random.urlsafe_base64 #=> "b4GOKm4pOYU_-BOXcrUGDg"
  #   # or
  #   prng = Random.new
  #   prng.urlsafe_base64 #=> "UZLdOkzop70Ddx-IJR0ABg"
  #
  #   prng.urlsafe_base64(nil, true) #=> "i0XQ-7gglIsHGV2_BNPrdQ=="
  #   prng.urlsafe_base64(nil, true) #=> "-M8rLhr7JEpJlqFGUMmOxg=="
  #
  # See RFC 3548 for the definition of URL-safe base64.
  def urlsafe_base64(n=nil, padding=false)
    s = [random_bytes(n)].pack("m0")
    s.tr!("+/", "-_")
    s.delete!("=") unless padding
    s
  end

  # Generate a random v4 UUID (Universally Unique IDentifier).
  #
  #   require 'random/formatter'
  #
  #   Random.uuid #=> "2d931510-d99f-494a-8c67-87feb05e1594"
  #   Random.uuid #=> "bad85eb9-0713-4da7-8d36-07a8e4b00eab"
  #   # or
  #   prng = Random.new
  #   prng.uuid #=> "62936e70-1815-439b-bf89-8492855a7e6b"
  #
  # The version 4 UUID is purely random (except the version).
  # It doesn't contain meaningful information such as MAC addresses, timestamps, etc.
  #
  # The result contains 122 random bits (15.25 random bytes).
  #
  # See RFC4122[https://datatracker.ietf.org/doc/html/rfc4122] for details of UUID.
  #
  def uuid
    ary = random_bytes(16).unpack("NnnnnN")
    ary[2] = (ary[2] & 0x0fff) | 0x4000
    ary[3] = (ary[3] & 0x3fff) | 0x8000
    "%08x-%04x-%04x-%04x-%04x%08x" % ary
  end

  private def gen_random(n)
    self.bytes(n)
  end

  # Generate a string that randomly draws from a
  # source array of characters.
  #
  # The argument _source_ specifies the array of characters from which
  # to generate the string.
  # The argument _n_ specifies the length, in characters, of the string to be
  # generated.
  #
  # The result may contain whatever characters are in the source array.
  #
  #   require 'random/formatter'
  #
  #   prng.choose([*'l'..'r'], 16) #=> "lmrqpoonmmlqlron"
  #   prng.choose([*'0'..'9'], 5)  #=> "27309"
  private def choose(source, n)
    size = source.size
    m = 1
    limit = size
    while limit * size <= 0x100000000
      limit *= size
      m += 1
    end
    result = ''.dup
    while m <= n
      rs = random_number(limit)
      is = rs.digits(size)
      (m-is.length).times { is << 0 }
      result << source.values_at(*is).join('')
      n -= m
    end
    if 0 < n
      rs = random_number(limit)
      is = rs.digits(size)
      if is.length < n
        (n-is.length).times { is << 0 }
      else
        is.pop while n < is.length
      end
      result.concat source.values_at(*is).join('')
    end
    result
  end

  ALPHANUMERIC = [*'A'..'Z', *'a'..'z', *'0'..'9']
  # Generate a random alphanumeric string.
  #
  # The argument _n_ specifies the length, in characters, of the alphanumeric
  # string to be generated.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The result may contain A-Z, a-z and 0-9.
  #
  #   require 'random/formatter'
  #
  #   Random.alphanumeric     #=> "2BuBuLf3WfSKyQbR"
  #   # or
  #   prng = Random.new
  #   prng.alphanumeric(10) #=> "i6K93NdqiH"
  def alphanumeric(n=nil)
    n = 16 if n.nil?
    choose(ALPHANUMERIC, n)
  end
end
