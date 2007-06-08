begin
  require 'openssl'
rescue LoadError
end

module SecRand
  def self.random_bytes(n=nil)
    n ||= 16
    if defined? OpenSSL::Random
      return OpenSSL::Random.random_bytes(n)
    end
    if !defined?(@has_urandom) || @has_urandom
      @has_urandom = false
      flags = File::RDONLY
      flags |= File::NONBLOCK if defined? File::NONBLOCK
      flags |= File::NOCTTY if defined? File::NOCTTY
      flags |= File::NOFOLLOW if defined? File::NOFOLLOW
      begin
        File.open("/dev/urandom", flags) {|f|
          unless f.stat.chardev?
            raise Errno::ENOENT
          end
          @has_urandom = true
          ret = f.readpartial(n)
          if ret.length != n
            raise NotImplementedError, "Unexpected partial read from random device"
          end
          return ret
        }
      rescue Errno::ENOENT
        raise NotImplementedError, "No random device"
      end
    end
    raise NotImplementedError, "No random device"
  end

  def self.hex(n=nil)
    random_bytes(n).unpack("H*")[0]
  end

  def self.base64(n=nil)
    [random_bytes(n)].pack("m*").delete("\n")
  end

end

def SecRand(n=0)
  if 0 < n
    hex = n.to_s(16)
    hex = '0' + hex if (hex.length & 1) == 1
    bin = [hex].pack("H*")
    mask = bin[0].ord
    mask |= mask >> 1
    mask |= mask >> 2
    mask |= mask >> 4
    begin
      rnd = SecRand.random_bytes(bin.length)
      rnd[0] = (rnd[0].ord & mask).chr
    end until rnd < bin
    rnd.unpack("H*")[0].hex
  else
    # assumption: Float::MANT_DIG <= 64
    i64 = SecRand.random_bytes(8).unpack("Q")[0]
    Math.ldexp(i64 >> (64-Float::MANT_DIG), -Float::MANT_DIG)
  end
end
