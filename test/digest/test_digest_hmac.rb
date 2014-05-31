require 'test/unit'
require 'digest/hmac'

module TM_HMAC
  def test_s_hexdigest
    cases.each { |h|
      digesters.each { |d|
        assert_equal(h[:hexdigest], Digest::HMAC.hexdigest(h[:data], h[:key], d))
      }
    }
  end

  def test_hexdigest
    cases.each { |h|
      digesters.each { |d|
        hmac = Digest::HMAC.new(h[:key], d)

        hmac.update(h[:data])

        assert_equal(h[:hexdigest], hmac.hexdigest)
      }
    }
  end

  def test_reset
    cases.each { |h|
      digesters.each { |d|
        hmac = Digest::HMAC.new(h[:key], d)
        hmac.update("test")
        hmac.reset
        hmac.update(h[:data])

        assert_equal(h[:hexdigest], hmac.hexdigest)
      }
    }
  end
end

class TC_HMAC_MD5 < Test::Unit::TestCase
  include TM_HMAC

  def digesters
    [Digest::MD5, Digest::MD5.new]
  end

  # Taken from RFC 2202: Test Cases for HMAC-MD5 and HMAC-SHA-1
  def cases
    [
     {
       :key		=> "\x0b" * 16,
       :data		=> "Hi There",
       :hexdigest	=> "9294727a3638bb1c13f48ef8158bfc9d",
     }, {
       :key		=> "Jefe",
       :data		=> "what do ya want for nothing?",
       :hexdigest	=> "750c783e6ab0b503eaa86e310a5db738",
     }, {
       :key		=> "\xaa" * 16,
       :data		=> "\xdd" * 50,
       :hexdigest	=> "56be34521d144c88dbb8c733f0e8b3f6",
     }, {
       :key		=> "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19",
       :data		=> "\xcd" * 50,
       :hexdigest	=> "697eaf0aca3a3aea3a75164746ffaa79",
     }, {
       :key		=> "\x0c" * 16,
       :data		=> "Test With Truncation",
       :hexdigest	=> "56461ef2342edc00f9bab995690efd4c",
     }, {
       :key		=> "\xaa" * 80,
       :data		=> "Test Using Larger Than Block-Size Key - Hash Key First",
       :hexdigest	=> "6b1ab7fe4bd7bf8f0b62e6ce61b9d0cd",
     }, {
       :key		=> "\xaa" * 80,
       :data		=> "Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data",
       :hexdigest	=> "6f630fad67cda0ee1fb1f562db3aa53e",
     }
    ]
  end
end

class TC_HMAC_SHA1 < Test::Unit::TestCase
  include TM_HMAC

  def digesters
    [Digest::SHA1, Digest::SHA1.new]
  end

  # Taken from RFC 2202: Test Cases for HMAC-MD5 and HMAC-SHA-1
  def cases
    [
     {
       :key		=> "\x0b" * 20,
       :data		=> "Hi There",
       :hexdigest	=> "b617318655057264e28bc0b6fb378c8ef146be00",
     }, {
       :key		=> "Jefe",
       :data		=> "what do ya want for nothing?",
       :hexdigest	=> "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79",
     }, {
       :key		=> "\xaa" * 20,
       :data		=> "\xdd" * 50,
       :hexdigest	=> "125d7342b9ac11cd91a39af48aa17b4f63f175d3",
     }, {
       :key		=> "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19",
       :data		=> "\xcd" * 50,
       :hexdigest	=> "4c9007f4026250c6bc8414f9bf50c86c2d7235da",
     }, {
       :key		=> "\x0c" * 20,
       :data		=> "Test With Truncation",
       :hexdigest	=> "4c1a03424b55e07fe7f27be1d58bb9324a9a5a04",
     }, {
       :key		=> "\xaa" * 80,
       :data		=> "Test Using Larger Than Block-Size Key - Hash Key First",
       :hexdigest	=> "aa4ae5e15272d00e95705637ce8a3b55ed402112",
     }, {
       :key		=> "\xaa" * 80,
       :data		=> "Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data",
       :hexdigest	=> "e8e99d0f45237d786d6bbaa7965c7808bbff1a91",
     }
    ]
  end
end

class TC_HMAC_RMD160 < Test::Unit::TestCase
  include TM_HMAC

  def digesters
    [Digest::RMD160, Digest::RMD160.new]
  end

  # Taken from RFC 2286: Test Cases for HMAC-RIPEMD160 and HMAC-RIPEMD128
  def cases
    [
     {
       :key		=> "\x0b" * 20,
       :data		=> "Hi There",
       :hexdigest	=> "24cb4bd67d20fc1a5d2ed7732dcc39377f0a5668",
     }, {
       :key		=> "Jefe",
       :data		=> "what do ya want for nothing?",
       :hexdigest	=> "dda6c0213a485a9e24f4742064a7f033b43c4069",
     }, {
       :key		=> "\xaa" * 20,
       :data		=> "\xdd" * 50,
       :hexdigest	=> "b0b105360de759960ab4f35298e116e295d8e7c1",
     }, {
       :key		=> "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19",
       :data		=> "\xcd" * 50,
       :hexdigest	=> "d5ca862f4d21d5e610e18b4cf1beb97a4365ecf4",
     }, {
       :key		=> "\x0c" * 20,
       :data		=> "Test With Truncation",
       :hexdigest	=> "7619693978f91d90539ae786500ff3d8e0518e39",
     }, {
       :key		=> "\xaa" * 80,
       :data		=> "Test Using Larger Than Block-Size Key - Hash Key First",
       :hexdigest	=> "6466ca07ac5eac29e1bd523e5ada7605b791fd8b",
     }, {
       :key		=> "\xaa" * 80,
       :data		=> "Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data",
       :hexdigest	=> "69ea60798d71616cce5fd0871e23754cd75d5a0a",
     }
    ]
  end
end
