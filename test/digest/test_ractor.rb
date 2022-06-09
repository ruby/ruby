# frozen_string_literal: true
require 'test/unit'

require 'digest'
%w[digest/md5 digest/rmd160 digest/sha1 digest/sha2 digest/bubblebabble].each do |lib|
  begin
    require lib
  rescue LoadError
  end
end

module TestDigestRactor
  Data1 = "abc"
  Data2 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"

  def setup
    pend unless defined?(Ractor)
  end

  def test_s_hexdigest
    assert_in_out_err([], <<-"end;", ["true", "true"], [])
      $VERBOSE = nil
      require "digest"
      require "#{self.class::LIB}"
      DATA = #{self.class::DATA.inspect}
      rs = DATA.map do |str, hexdigest|
        r = Ractor.new str do |x|
          #{self.class::ALGO}.hexdigest(x)
        end
        [r, hexdigest]
      end
      rs.each do |r, hexdigest|
        puts r.take == hexdigest
      end
    end;
  end

  class TestMD5Ractor < Test::Unit::TestCase
    include TestDigestRactor
    LIB = "digest/md5"
    ALGO = Digest::MD5
    DATA = {
      Data1 => "900150983cd24fb0d6963f7d28e17f72",
      Data2 => "8215ef0796a20bcaaae116d3876c664a",
    }
  end if defined?(Digest::MD5)

  class TestSHA1Ractor < Test::Unit::TestCase
    include TestDigestRactor
    LIB = "digest/sha1"
    ALGO = Digest::SHA1
    DATA = {
      Data1 => "a9993e364706816aba3e25717850c26c9cd0d89d",
      Data2 => "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
    }
  end if defined?(Digest::SHA1)

  class TestSHA256Ractor < Test::Unit::TestCase
    include TestDigestRactor
    LIB = "digest/sha2"
    ALGO = Digest::SHA256
    DATA = {
      Data1 => "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      Data2 => "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    }
  end if defined?(Digest::SHA256)

  class TestSHA384Ractor < Test::Unit::TestCase
    include TestDigestRactor
    LIB = "digest/sha2"
    ALGO = Digest::SHA384
    DATA = {
      Data1 => "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"\
               "8086072ba1e7cc2358baeca134c825a7",
      Data2 => "3391fdddfc8dc7393707a65b1b4709397cf8b1d162af05abfe8f450de5f36bc6"\
               "b0455a8520bc4e6f5fe95b1fe3c8452b",
    }
  end if defined?(Digest::SHA384)

  class TestSHA512Ractor < Test::Unit::TestCase
    include TestDigestRactor
    LIB = "digest/sha2"
    ALGO = Digest::SHA512
    DATA = {
      Data1 => "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"\
               "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
      Data2 => "204a8fc6dda82f0a0ced7beb8e08a41657c16ef468b228a8279be331a703c335"\
               "96fd15c13b1b07f9aa1d3bea57789ca031ad85c7a71dd70354ec631238ca3445",
    }
  end if defined?(Digest::SHA512)

  class TestRMD160Ractor < Test::Unit::TestCase
    include TestDigestRactor
    LIB = "digest/rmd160"
    ALGO = Digest::RMD160
    DATA = {
      Data1 => "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc",
      Data2 => "12a053384a9c0c88e405a06c27dcf49ada62eb2b",
    }
  end if defined?(Digest::RMD160)
end
