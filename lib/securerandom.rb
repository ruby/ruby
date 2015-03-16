# -*- coding: us-ascii -*-
begin
  require 'openssl'
rescue LoadError
end

# == Secure random number generator interface.
#
# This library is an interface to secure random number generators which are
# suitable for generating session keys in HTTP cookies, etc.
#
# You can use this library in your application by requiring it:
#
#   require 'securerandom'
#
# It supports the following secure random number generators:
#
# * openssl
# * /dev/urandom
# * Win32
#
# === Examples
#
# Generate random hexadecimal strings:
#
#   require 'securerandom'
#
#   p SecureRandom.hex(10) #=> "52750b30ffbc7de3b362"
#   p SecureRandom.hex(10) #=> "92b15d6c8dc4beb5f559"
#   p SecureRandom.hex(13) #=> "39b290146bea6ce975c37cfc23"
#
# Generate random base64 strings:
#
#   p SecureRandom.base64(10) #=> "EcmTPZwWRAozdA=="
#   p SecureRandom.base64(10) #=> "KO1nIU+p9DKxGg=="
#   p SecureRandom.base64(12) #=> "7kJSM/MzBJI+75j8"
#
# Generate random binary strings:
#
#   p SecureRandom.random_bytes(10) #=> "\016\t{\370g\310pbr\301"
#   p SecureRandom.random_bytes(10) #=> "\323U\030TO\234\357\020\a\337"
#
# Generate UUIDs:
#
#   p SecureRandom.uuid #=> "2d931510-d99f-494a-8c67-87feb05e1594"
#   p SecureRandom.uuid #=> "bad85eb9-0713-4da7-8d36-07a8e4b00eab"
#

module SecureRandom
  if defined? OpenSSL::Random
    def self.gen_random(n)
      @pid = 0 unless defined?(@pid)
      pid = $$
      unless @pid == pid
        now = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
        ary = [now, @pid, pid]
        OpenSSL::Random.random_add(ary.join("").to_s, 0.0)
        @pid = pid
      end
      return OpenSSL::Random.random_bytes(n)
    end
  else
    def self.gen_random(n)
      ret = Random.raw_seed(n)
      unless ret
        raise NotImplementedError, "No random device"
      end
      unless ret.length == n
        raise NotImplementedError, "Unexpected partial read from random device: only #{ret.length} for #{n} bytes"
      end
      ret
    end
  end
end

module Random::Formatter

  # SecureRandom.random_bytes generates a random binary string.
  #
  # The argument _n_ specifies the length of the result string.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in future.
  #
  # The result may contain any byte: "\x00" - "\xff".
  #
  #   p SecureRandom.random_bytes #=> "\xD8\\\xE0\xF4\r\xB2\xFC*WM\xFF\x83\x18\xF45\xB6"
  #   p SecureRandom.random_bytes #=> "m\xDC\xFC/\a\x00Uf\xB2\xB2P\xBD\xFF6S\x97"
  #
  # If a secure random number generator is not available,
  # +NotImplementedError+ is raised.
  def random_bytes(n=nil)
    n = n ? n.to_int : 16
    gen_random(n)
  end

  # SecureRandom.hex generates a random hexadecimal string.
  #
  # The argument _n_ specifies the length, in bytes, of the random number to be generated.
  # The length of the resulting hexadecimal string is twice of _n_.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The result may contain 0-9 and a-f.
  #
  #   p SecureRandom.hex #=> "eb693ec8252cd630102fd0d0fb7c3485"
  #   p SecureRandom.hex #=> "91dc3bfb4de5b11d029d376634589b61"
  #
  # If a secure random number generator is not available,
  # +NotImplementedError+ is raised.
  def hex(n=nil)
    random_bytes(n).unpack("H*")[0]
  end

  # SecureRandom.base64 generates a random base64 string.
  #
  # The argument _n_ specifies the length, in bytes, of the random number
  # to be generated. The length of the result string is about 4/3 of _n_.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The result may contain A-Z, a-z, 0-9, "+", "/" and "=".
  #
  #   p SecureRandom.base64 #=> "/2BuBuLf3+WfSKyQbRcc/A=="
  #   p SecureRandom.base64 #=> "6BbW0pxO0YENxn38HMUbcQ=="
  #
  # If a secure random number generator is not available,
  # +NotImplementedError+ is raised.
  #
  # See RFC 3548 for the definition of base64.
  def base64(n=nil)
    [random_bytes(n)].pack("m*").delete("\n")
  end

  # SecureRandom.urlsafe_base64 generates a random URL-safe base64 string.
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
  #   p SecureRandom.urlsafe_base64 #=> "b4GOKm4pOYU_-BOXcrUGDg"
  #   p SecureRandom.urlsafe_base64 #=> "UZLdOkzop70Ddx-IJR0ABg"
  #
  #   p SecureRandom.urlsafe_base64(nil, true) #=> "i0XQ-7gglIsHGV2_BNPrdQ=="
  #   p SecureRandom.urlsafe_base64(nil, true) #=> "-M8rLhr7JEpJlqFGUMmOxg=="
  #
  # If a secure random number generator is not available,
  # +NotImplementedError+ is raised.
  #
  # See RFC 3548 for the definition of URL-safe base64.
  def urlsafe_base64(n=nil, padding=false)
    s = [random_bytes(n)].pack("m*")
    s.delete!("\n")
    s.tr!("+/", "-_")
    s.delete!("=") unless padding
    s
  end

=begin
  # SecureRandom.random_number generates a random number.
  #
  # If a positive integer is given as _n_,
  # +SecureRandom.random_number+ returns an integer, such that:
  # +0 <= SecureRandom.random_number(n) < n+.
  #
  #   p SecureRandom.random_number(100) #=> 15
  #   p SecureRandom.random_number(100) #=> 88
  #
  # If 0 is given or an argument is not given,
  # +SecureRandom.random_number+ returns a float, such that:
  # +0.0 <= SecureRandom.random_number() < 1.0+.
  #
  #   p SecureRandom.random_number #=> 0.596506046187744
  #   p SecureRandom.random_number #=> 0.350621695741409
  #
  def random_number(n=0)
    if 0 < n
      if defined? OpenSSL::BN
        OpenSSL::BN.rand_range(n).to_i
      else
        hex = n.to_s(16)
        hex = '0' + hex if (hex.length & 1) == 1
        bin = [hex].pack("H*")
        mask = bin[0].ord
        mask |= mask >> 1
        mask |= mask >> 2
        mask |= mask >> 4
        begin
          rnd = random_bytes(bin.length)
          rnd[0] = (rnd[0].ord & mask).chr
        end until rnd < bin
        rnd.unpack("H*")[0].hex
      end
    else
      # assumption: Float::MANT_DIG <= 64
      if defined? OpenSSL::BN
        i64 = OpenSSL::BN.rand(64, -1).to_i
      else
        i64 = random_bytes(8).unpack("Q")[0]
      end
      Math.ldexp(i64 >> (64-Float::MANT_DIG), -Float::MANT_DIG)
    end
  end
=end

  # SecureRandom.uuid generates a random v4 UUID (Universally Unique IDentifier).
  #
  #   p SecureRandom.uuid #=> "2d931510-d99f-494a-8c67-87feb05e1594"
  #   p SecureRandom.uuid #=> "bad85eb9-0713-4da7-8d36-07a8e4b00eab"
  #   p SecureRandom.uuid #=> "62936e70-1815-439b-bf89-8492855a7e6b"
  #
  # The version 4 UUID is purely random (except the version).
  # It doesn't contain meaningful information such as MAC addresses, timestamps, etc.
  #
  # See RFC 4122 for details of UUID.
  #
  def uuid
    ary = random_bytes(16).unpack("NnnnnN")
    ary[2] = (ary[2] & 0x0fff) | 0x4000
    ary[3] = (ary[3] & 0x3fff) | 0x8000
    "%08x-%04x-%04x-%04x-%04x%08x" % ary
  end

  private
  def gen_random(n)
    self.bytes(n)
  end
end

SecureRandom.extend(Random::Formatter)
