# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestCipher < OpenSSL::TestCase

  @ciphers = OpenSSL::Cipher.ciphers

  class << self

    def has_cipher?(name)
      @ciphers.include?(name)
    end

    def has_ciphers?(list)
      list.all? { |name| has_cipher?(name) }
    end

  end

  def setup
    @c1 = OpenSSL::Cipher.new("DES-EDE3-CBC")
    @c2 = OpenSSL::Cipher::DES.new(:EDE3, "CBC")
    @key = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
    @iv = "\0\0\0\0\0\0\0\0"
    @hexkey = "0000000000000000000000000000000000000000000000"
    @hexiv = "0000000000000000"
    @data = "DATA"
  end

  def teardown
    super
    @c1 = @c2 = nil
  end

  def test_crypt
    @c1.encrypt.pkcs5_keyivgen(@key, @iv)
    @c2.encrypt.pkcs5_keyivgen(@key, @iv)
    s1 = @c1.update(@data) + @c1.final
    s2 = @c2.update(@data) + @c2.final
    assert_equal(s1, s2, "encrypt")

    @c1.decrypt.pkcs5_keyivgen(@key, @iv)
    @c2.decrypt.pkcs5_keyivgen(@key, @iv)
    assert_equal(@data, @c1.update(s1)+@c1.final, "decrypt")
    assert_equal(@data, @c2.update(s2)+@c2.final, "decrypt")
  end

  def test_info
    assert_equal("DES-EDE3-CBC", @c1.name, "name")
    assert_equal("DES-EDE3-CBC", @c2.name, "name")
    assert_kind_of(Integer, @c1.key_len, "key_len")
    assert_kind_of(Integer, @c1.iv_len, "iv_len")
  end

  def test_dup
    assert_equal(@c1.name, @c1.dup.name, "dup")
    assert_equal(@c1.name, @c1.clone.name, "clone")
    @c1.encrypt
    @c1.key = @key
    @c1.iv = @iv
    tmpc = @c1.dup
    s1 = @c1.update(@data) + @c1.final
    s2 = tmpc.update(@data) + tmpc.final
    assert_equal(s1, s2, "encrypt dup")
  end

  def test_reset
    @c1.encrypt
    @c1.key = @key
    @c1.iv = @iv
    s1 = @c1.update(@data) + @c1.final
    @c1.reset
    s2 = @c1.update(@data) + @c1.final
    assert_equal(s1, s2, "encrypt reset")
  end

  def test_key_iv_set
    # default value for DES-EDE3-CBC
    assert_equal(24, @c1.key_len)
    assert_equal(8, @c1.iv_len)
    assert_raise(ArgumentError) { @c1.key = "\x01" * 23 }
    @c1.key = "\x01" * 24
    assert_raise(ArgumentError) { @c1.key = "\x01" * 25 }
    assert_raise(ArgumentError) { @c1.iv = "\x01" * 7 }
    @c1.iv = "\x01" * 8
    assert_raise(ArgumentError) { @c1.iv = "\x01" * 9 }
  end

  def test_empty_data
    @c1.encrypt
    assert_raise(ArgumentError){ @c1.update("") }
  end

  def test_initialize
    assert_raise(RuntimeError) {@c1.__send__(:initialize, "DES-EDE3-CBC")}
    assert_raise(RuntimeError) {OpenSSL::Cipher.allocate.final}
  end

  def test_ctr_if_exists
    begin
      cipher = OpenSSL::Cipher.new('aes-128-ctr')
      cipher.encrypt
      cipher.pkcs5_keyivgen('password')
      c = cipher.update('hello,world') + cipher.final
      cipher.decrypt
      cipher.pkcs5_keyivgen('password')
      assert_equal('hello,world', cipher.update(c) + cipher.final)
    end
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

  def test_AES_crush
    500.times do
      assert_nothing_raised("[Bug #2768]") do
        # it caused OpenSSL SEGV by uninitialized key
        OpenSSL::Cipher::AES128.new("ECB").update "." * 17
      end
    end
  end

  if has_ciphers?(['aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm'])

    def test_authenticated
      cipher = OpenSSL::Cipher.new('aes-128-gcm')
      assert_predicate(cipher, :authenticated?)
      cipher = OpenSSL::Cipher.new('aes-128-cbc')
      assert_not_predicate(cipher, :authenticated?)
    end

    def test_aes_gcm
      ['aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm'].each do |algo|
        pt = "You should all use Authenticated Encryption!"
        cipher, key, iv = new_encryptor(algo)

        cipher.auth_data = "aad"
        ct  = cipher.update(pt) + cipher.final
        tag = cipher.auth_tag
        assert_equal(16, tag.size)

        decipher = new_decryptor(algo, key, iv)
        decipher.auth_tag = tag
        decipher.auth_data = "aad"

        assert_equal(pt, decipher.update(ct) + decipher.final)
      end
    end

    def test_aes_gcm_short_tag
      ['aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm'].each do |algo|
        pt = "You should all use Authenticated Encryption!"
        cipher, key, iv = new_encryptor(algo)

        cipher.auth_data = "aad"
        ct  = cipher.update(pt) + cipher.final
        tag = cipher.auth_tag(8)
        assert_equal(8, tag.size)

        decipher = new_decryptor(algo, key, iv)
        decipher.auth_tag = tag
        decipher.auth_data = "aad"

        assert_equal(pt, decipher.update(ct) + decipher.final)
      end
    end

    def test_aes_gcm_wrong_tag
      pt = "You should all use Authenticated Encryption!"
      cipher, key, iv = new_encryptor('aes-128-gcm')

      cipher.auth_data = "aad"
      ct  = cipher.update(pt) + cipher.final
      tag = cipher.auth_tag

      decipher = new_decryptor('aes-128-gcm', key, iv)
      tag.setbyte(-1, (tag.getbyte(-1) + 1) & 0xff)
      decipher.auth_tag = tag
      decipher.auth_data = "aad"

      assert_raise OpenSSL::Cipher::CipherError do
        decipher.update(ct) + decipher.final
      end
    end

    def test_aes_gcm_wrong_auth_data
      pt = "You should all use Authenticated Encryption!"
      cipher, key, iv = new_encryptor('aes-128-gcm')

      cipher.auth_data = "aad"
      ct  = cipher.update(pt) + cipher.final
      tag = cipher.auth_tag

      decipher = new_decryptor('aes-128-gcm', key, iv)
      decipher.auth_tag = tag
      decipher.auth_data = "daa"

      assert_raise OpenSSL::Cipher::CipherError do
        decipher.update(ct) + decipher.final
      end
    end

    def test_aes_gcm_wrong_ciphertext
      pt = "You should all use Authenticated Encryption!"
      cipher, key, iv = new_encryptor('aes-128-gcm')

      cipher.auth_data = "aad"
      ct  = cipher.update(pt) + cipher.final
      tag = cipher.auth_tag

      decipher = new_decryptor('aes-128-gcm', key, iv)
      decipher.auth_tag = tag
      decipher.auth_data = "aad"

      assert_raise OpenSSL::Cipher::CipherError do
        decipher.update(ct[0..-2] << ct[-1].succ) + decipher.final
      end
    end

    def test_aes_gcm_variable_iv_len
      pt = "You should all use Authenticated Encryption!"
      cipher = OpenSSL::Cipher.new("aes-128-gcm").encrypt
      cipher.key = "x" * 16
      assert_equal(12, cipher.iv_len)
      cipher.iv = "a" * 12
      ct1 = cipher.update(pt) << cipher.final
      tag1 = cipher.auth_tag

      cipher = OpenSSL::Cipher.new("aes-128-gcm").encrypt
      cipher.key = "x" * 16
      cipher.iv_len = 10
      assert_equal(10, cipher.iv_len)
      cipher.iv = "a" * 10
      ct2 = cipher.update(pt) << cipher.final
      tag2 = cipher.auth_tag

      assert_not_equal ct1, ct2
      assert_not_equal tag1, tag2

      decipher = OpenSSL::Cipher.new("aes-128-gcm").decrypt
      decipher.auth_tag = tag1
      decipher.key = "x" * 16
      decipher.iv_len = 12
      decipher.iv = "a" * 12
      assert_equal(pt, decipher.update(ct1) << decipher.final)

      decipher.reset
      decipher.auth_tag = tag2
      assert_raise(OpenSSL::Cipher::CipherError) {
        decipher.update(ct2) << decipher.final
      }

      decipher.reset
      decipher.auth_tag = tag2
      decipher.iv_len = 10
      decipher.iv = "a" * 10
      assert_equal(pt, decipher.update(ct2) << decipher.final)
    end

  end

  def test_aes_ocb_tag_len
    pt = "You should all use Authenticated Encryption!"
    cipher = OpenSSL::Cipher.new("aes-128-ocb").encrypt
    cipher.auth_tag_len = 14
    cipher.iv_len = 8
    key = cipher.random_key
    iv = cipher.random_iv
    cipher.auth_data = "aad"
    ct  = cipher.update(pt) + cipher.final
    tag = cipher.auth_tag
    assert_equal(14, tag.size)

    decipher = OpenSSL::Cipher.new("aes-128-ocb").decrypt
    decipher.auth_tag_len = 14
    decipher.auth_tag = tag
    decipher.iv_len = 8
    decipher.key = key
    decipher.iv = iv
    decipher.auth_data = "aad"
    assert_equal(pt, decipher.update(ct) + decipher.final)

    decipher = OpenSSL::Cipher.new("aes-128-ocb").decrypt
    decipher.auth_tag_len = 9
    decipher.auth_tag = tag[0, 9]
    decipher.iv_len = 8
    decipher.key = key
    decipher.iv = iv
    decipher.auth_data = "aad"
    assert_raise(OpenSSL::Cipher::CipherError) {
      decipher.update(ct) + decipher.final
    }
  end if has_cipher?("aes-128-ocb")

  private

  def new_encryptor(algo)
    cipher = OpenSSL::Cipher.new(algo)
    cipher.encrypt
    key = cipher.random_key
    iv = cipher.random_iv
    [cipher, key, iv]
  end

  def new_decryptor(algo, key, iv)
    OpenSSL::Cipher.new(algo).tap do |cipher|
      cipher.decrypt
      cipher.key = key
      cipher.iv = iv
    end
  end

end

end
