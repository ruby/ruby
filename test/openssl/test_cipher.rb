# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestCipher < OpenSSL::TestCase
  module Helper
    def has_cipher?(name)
      @ciphers ||= OpenSSL::Cipher.ciphers
      @ciphers.include?(name)
    end
  end
  include Helper
  extend Helper

  def test_encrypt_decrypt
    # NIST SP 800-38A F.2.1
    key = ["2b7e151628aed2a6abf7158809cf4f3c"].pack("H*")
    iv =  ["000102030405060708090a0b0c0d0e0f"].pack("H*")
    pt =  ["6bc1bee22e409f96e93d7e117393172a" \
           "ae2d8a571e03ac9c9eb76fac45af8e51"].pack("H*")
    ct =  ["7649abac8119b246cee98e9b12e9197d" \
           "5086cb9b507219ee95db113a917678b2"].pack("H*")
    cipher = new_encryptor("aes-128-cbc", key: key, iv: iv, padding: 0)
    assert_equal ct, cipher.update(pt) << cipher.final
    cipher = new_decryptor("aes-128-cbc", key: key, iv: iv, padding: 0)
    assert_equal pt, cipher.update(ct) << cipher.final
  end

  def test_pkcs5_keyivgen
    pass = "\x00" * 8
    salt = "\x01" * 8
    num = 2048
    pt = "data to be encrypted"
    cipher = OpenSSL::Cipher.new("DES-EDE3-CBC").encrypt
    cipher.pkcs5_keyivgen(pass, salt, num, "MD5")
    s1 = cipher.update(pt) << cipher.final

    d1 = num.times.inject(pass + salt) {|out, _| OpenSSL::Digest::MD5.digest(out) }
    d2 = num.times.inject(d1 + pass + salt) {|out, _| OpenSSL::Digest::MD5.digest(out) }
    key = (d1 + d2)[0, 24]
    iv = (d1 + d2)[24, 8]
    cipher = new_encryptor("DES-EDE3-CBC", key: key, iv: iv)
    s2 = cipher.update(pt) << cipher.final

    assert_equal s1, s2
  end

  def test_info
    cipher = OpenSSL::Cipher.new("DES-EDE3-CBC").encrypt
    assert_equal "DES-EDE3-CBC", cipher.name
    assert_equal 24, cipher.key_len
    assert_equal 8, cipher.iv_len
  end

  def test_dup
    cipher = OpenSSL::Cipher.new("aes-128-cbc").encrypt
    assert_equal cipher.name, cipher.dup.name
    cipher.encrypt
    cipher.random_key
    cipher.random_iv
    tmpc = cipher.dup
    s1 = cipher.update("data") + cipher.final
    s2 = tmpc.update("data") + tmpc.final
    assert_equal(s1, s2, "encrypt dup")
  end

  def test_reset
    cipher = OpenSSL::Cipher.new("aes-128-cbc").encrypt
    cipher.encrypt
    cipher.random_key
    cipher.random_iv
    s1 = cipher.update("data") + cipher.final
    cipher.reset
    s2 = cipher.update("data") + cipher.final
    assert_equal(s1, s2, "encrypt reset")
  end

  def test_key_iv_set
    cipher = OpenSSL::Cipher.new("DES-EDE3-CBC").encrypt
    assert_raise(ArgumentError) { cipher.key = "\x01" * 23 }
    assert_nothing_raised { cipher.key = "\x01" * 24 }
    assert_raise(ArgumentError) { cipher.key = "\x01" * 25 }
    assert_raise(ArgumentError) { cipher.iv = "\x01" * 7 }
    assert_nothing_raised { cipher.iv = "\x01" * 8 }
    assert_raise(ArgumentError) { cipher.iv = "\x01" * 9 }
  end

  def test_random_key_iv
    data = "data"
    s1, s2 = 2.times.map do
      cipher = OpenSSL::Cipher.new("aes-128-cbc").encrypt
      cipher.random_key
      cipher.iv = "\x01" * 16
      cipher.update(data) << cipher.final
    end
    assert_not_equal s1, s2

    s1, s2 = 2.times.map do
      cipher = OpenSSL::Cipher.new("aes-128-cbc").encrypt
      cipher.key = "\x01" * 16
      cipher.random_iv
      cipher.update(data) << cipher.final
    end
    assert_not_equal s1, s2
  end

  def test_empty_data
    cipher = OpenSSL::Cipher.new("DES-EDE3-CBC").encrypt
    cipher.random_key
    assert_raise(ArgumentError) { cipher.update("") }
  end

  def test_initialize
    cipher = OpenSSL::Cipher.new("DES-EDE3-CBC")
    assert_raise(RuntimeError) { cipher.__send__(:initialize, "DES-EDE3-CBC") }
    assert_raise(RuntimeError) { OpenSSL::Cipher.allocate.final }
  end

  def test_ctr_if_exists
    # NIST SP 800-38A F.5.1
    key = ["2b7e151628aed2a6abf7158809cf4f3c"].pack("H*")
    iv =  ["f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"].pack("H*")
    pt =  ["6bc1bee22e409f96e93d7e117393172a" \
           "ae2d8a571e03ac9c9eb76fac45af8e51"].pack("H*")
    ct =  ["874d6191b620e3261bef6864990db6ce" \
           "9806f66b7970fdff8617187bb9fffdff"].pack("H*")
    cipher = new_encryptor("aes-128-ctr", key: key, iv: iv, padding: 0)
    assert_equal ct, cipher.update(pt) << cipher.final
    cipher = new_decryptor("aes-128-ctr", key: key, iv: iv, padding: 0)
    assert_equal pt, cipher.update(ct) << cipher.final
  end if has_cipher?('aes-128-ctr')

  def test_ciphers
    OpenSSL::Cipher.ciphers.each{|name|
      next if /netbsd/ =~ RUBY_PLATFORM && /idea|rc5/i =~ name
      begin
        assert_kind_of(OpenSSL::Cipher, OpenSSL::Cipher.new(name))
      rescue OpenSSL::Cipher::CipherError => e
        raise unless /wrap/ =~ name and /wrap mode not allowed/ =~ e.message
      end
    }
  end

  def test_AES
    pt = File.read(__FILE__)
    %w(ECB CBC CFB OFB).each{|mode|
      c1 = OpenSSL::Cipher::AES256.new(mode)
      c1.encrypt
      c1.pkcs5_keyivgen("passwd")
      ct = c1.update(pt) + c1.final

      c2 = OpenSSL::Cipher::AES256.new(mode)
      c2.decrypt
      c2.pkcs5_keyivgen("passwd")
      assert_equal(pt, c2.update(ct) + c2.final)
    }
  end

  def test_update_raise_if_key_not_set
    assert_raise(OpenSSL::Cipher::CipherError) do
      # it caused OpenSSL SEGV by uninitialized key [Bug #2768]
      OpenSSL::Cipher::AES128.new("ECB").update "." * 17
    end
  end

  def test_authenticated
    if has_cipher?('aes-128-gcm')
      cipher = OpenSSL::Cipher.new('aes-128-gcm')
      assert_predicate(cipher, :authenticated?)
    end
    cipher = OpenSSL::Cipher.new('aes-128-cbc')
    assert_not_predicate(cipher, :authenticated?)
  end

  def test_aes_gcm
    # GCM spec Appendix B Test Case 4
    key = ["feffe9928665731c6d6a8f9467308308"].pack("H*")
    iv =  ["cafebabefacedbaddecaf888"].pack("H*")
    aad = ["feedfacedeadbeeffeedfacedeadbeef" \
           "abaddad2"].pack("H*")
    pt =  ["d9313225f88406e5a55909c5aff5269a" \
           "86a7a9531534f7da2e4c303d8a318a72" \
           "1c3c0c95956809532fcf0e2449a6b525" \
           "b16aedf5aa0de657ba637b39"].pack("H*")
    ct =  ["42831ec2217774244b7221b784d0d49c" \
           "e3aa212f2c02a4e035c17e2329aca12e" \
           "21d514b25466931c7d8f6a5aac84aa05" \
           "1ba30b396a0aac973d58e091"].pack("H*")
    tag = ["5bc94fbc3221a5db94fae95ae7121a47"].pack("H*")

    cipher = new_encryptor("aes-128-gcm", key: key, iv: iv, auth_data: aad)
    assert_equal ct, cipher.update(pt) << cipher.final
    assert_equal tag, cipher.auth_tag
    cipher = new_decryptor("aes-128-gcm", key: key, iv: iv, auth_tag: tag, auth_data: aad)
    assert_equal pt, cipher.update(ct) << cipher.final

    # truncated tag is accepted
    cipher = new_encryptor("aes-128-gcm", key: key, iv: iv, auth_data: aad)
    assert_equal ct, cipher.update(pt) << cipher.final
    assert_equal tag[0, 8], cipher.auth_tag(8)
    cipher = new_decryptor("aes-128-gcm", key: key, iv: iv, auth_tag: tag[0, 8], auth_data: aad)
    assert_equal pt, cipher.update(ct) << cipher.final

    # wrong tag is rejected
    tag2 = tag.dup
    tag2.setbyte(-1, (tag2.getbyte(-1) + 1) & 0xff)
    cipher = new_decryptor("aes-128-gcm", key: key, iv: iv, auth_tag: tag2, auth_data: aad)
    cipher.update(ct)
    assert_raise(OpenSSL::Cipher::CipherError) { cipher.final }

    # wrong aad is rejected
    aad2 = aad[0..-2] << aad[-1].succ
    cipher = new_decryptor("aes-128-gcm", key: key, iv: iv, auth_tag: tag, auth_data: aad2)
    cipher.update(ct)
    assert_raise(OpenSSL::Cipher::CipherError) { cipher.final }

    # wrong ciphertext is rejected
    ct2 = ct[0..-2] << ct[-1].succ
    cipher = new_decryptor("aes-128-gcm", key: key, iv: iv, auth_tag: tag, auth_data: aad)
    cipher.update(ct2)
    assert_raise(OpenSSL::Cipher::CipherError) { cipher.final }
  end if has_cipher?("aes-128-gcm")

  def test_aes_gcm_variable_iv_len
    # GCM spec Appendix B Test Case 5
    key = ["feffe9928665731c6d6a8f9467308308"].pack("H*")
    iv  = ["cafebabefacedbad"].pack("H*")
    aad = ["feedfacedeadbeeffeedfacedeadbeef" \
           "abaddad2"].pack("H*")
    pt =  ["d9313225f88406e5a55909c5aff5269a" \
           "86a7a9531534f7da2e4c303d8a318a72" \
           "1c3c0c95956809532fcf0e2449a6b525" \
           "b16aedf5aa0de657ba637b39"].pack("H*")
    ct =  ["61353b4c2806934a777ff51fa22a4755" \
           "699b2a714fcdc6f83766e5f97b6c7423" \
           "73806900e49f24b22b097544d4896b42" \
           "4989b5e1ebac0f07c23f4598"].pack("H*")
    tag = ["3612d2e79e3b0785561be14aaca2fccb"].pack("H*")

    cipher = new_encryptor("aes-128-gcm", key: key, iv_len: 8, iv: iv, auth_data: aad)
    assert_equal ct, cipher.update(pt) << cipher.final
    assert_equal tag, cipher.auth_tag
    cipher = new_decryptor("aes-128-gcm", key: key, iv_len: 8, iv: iv, auth_tag: tag, auth_data: aad)
    assert_equal pt, cipher.update(ct) << cipher.final
  end if has_cipher?("aes-128-gcm")

  def test_aes_ocb_tag_len
    # RFC 7253 Appendix A; the second sample
    key = ["000102030405060708090A0B0C0D0E0F"].pack("H*")
    iv  = ["BBAA99887766554433221101"].pack("H*")
    aad = ["0001020304050607"].pack("H*")
    pt =  ["0001020304050607"].pack("H*")
    ct =  ["6820B3657B6F615A"].pack("H*")
    tag = ["5725BDA0D3B4EB3A257C9AF1F8F03009"].pack("H*")

    cipher = new_encryptor("aes-128-ocb", key: key, iv: iv, auth_data: aad)
    assert_equal ct, cipher.update(pt) << cipher.final
    assert_equal tag, cipher.auth_tag
    cipher = new_decryptor("aes-128-ocb", key: key, iv: iv, auth_tag: tag, auth_data: aad)
    assert_equal pt, cipher.update(ct) << cipher.final

    # RFC 7253 Appendix A; with 96 bits tag length
    key = ["0F0E0D0C0B0A09080706050403020100"].pack("H*")
    iv  = ["BBAA9988776655443322110D"].pack("H*")
    aad = ["000102030405060708090A0B0C0D0E0F1011121314151617" \
           "18191A1B1C1D1E1F2021222324252627"].pack("H*")
    pt =  ["000102030405060708090A0B0C0D0E0F1011121314151617" \
           "18191A1B1C1D1E1F2021222324252627"].pack("H*")
    ct =  ["1792A4E31E0755FB03E31B22116E6C2DDF9EFD6E33D536F1" \
           "A0124B0A55BAE884ED93481529C76B6A"].pack("H*")
    tag = ["D0C515F4D1CDD4FDAC4F02AA"].pack("H*")

    cipher = new_encryptor("aes-128-ocb", auth_tag_len: 12, key: key, iv: iv, auth_data: aad)
    assert_equal ct, cipher.update(pt) << cipher.final
    assert_equal tag, cipher.auth_tag
    cipher = new_decryptor("aes-128-ocb", auth_tag_len: 12, key: key, iv: iv, auth_tag: tag, auth_data: aad)
    assert_equal pt, cipher.update(ct) << cipher.final

  end if has_cipher?("aes-128-ocb")

  def test_aes_gcm_key_iv_order_issue
    pt = "[ruby/openssl#49]"
    cipher = OpenSSL::Cipher.new("aes-128-gcm").encrypt
    cipher.key = "x" * 16
    cipher.iv = "a" * 12
    ct1 = cipher.update(pt) << cipher.final
    tag1 = cipher.auth_tag

    cipher = OpenSSL::Cipher.new("aes-128-gcm").encrypt
    cipher.iv = "a" * 12
    cipher.key = "x" * 16
    ct2 = cipher.update(pt) << cipher.final
    tag2 = cipher.auth_tag

    assert_equal ct1, ct2
    assert_equal tag1, tag2
  end if has_cipher?("aes-128-gcm")

  def test_non_aead_cipher_set_auth_data
    assert_raise(OpenSSL::Cipher::CipherError) {
      cipher = OpenSSL::Cipher.new("aes-128-cfb").encrypt
      cipher.auth_data = "123"
    }
  end if has_cipher?("aes-128-gcm")

  private

  def new_encryptor(algo, **kwargs)
    OpenSSL::Cipher.new(algo).tap do |cipher|
      cipher.encrypt
      kwargs.each {|k, v| cipher.send(:"#{k}=", v) }
    end
  end

  def new_decryptor(algo, **kwargs)
    OpenSSL::Cipher.new(algo).tap do |cipher|
      cipher.decrypt
      kwargs.each {|k, v| cipher.send(:"#{k}=", v) }
    end
  end

end

end
