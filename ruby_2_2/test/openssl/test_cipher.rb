require_relative 'utils'

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestCipher < Test::Unit::TestCase

  class << self

    def has_cipher?(name)
      ciphers = OpenSSL::Cipher.ciphers
      # redefine method so we can use the cached ciphers value from the closure
      # and need not recompute the list each time
      define_singleton_method :has_cipher? do |name|
        ciphers.include?(name)
      end
      has_cipher?(name)
    end

    def has_ciphers?(list)
      list.all? { |name| has_cipher?(name) }
    end

  end

  def setup
    @c1 = OpenSSL::Cipher::Cipher.new("DES-EDE3-CBC")
    @c2 = OpenSSL::Cipher::DES.new(:EDE3, "CBC")
    @key = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
    @iv = "\0\0\0\0\0\0\0\0"
    @hexkey = "0000000000000000000000000000000000000000000000"
    @hexiv = "0000000000000000"
    @data = "DATA"
  end

  def teardown
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
    assert_kind_of(Fixnum, @c1.key_len, "key_len")
    assert_kind_of(Fixnum, @c1.iv_len, "iv_len")
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

  if OpenSSL::OPENSSL_VERSION_NUMBER > 0x00907000
    def test_ciphers
      OpenSSL::Cipher.ciphers.each{|name|
        next if /netbsd/ =~ RUBY_PLATFORM && /idea|rc5/i =~ name
        begin
          assert_kind_of(OpenSSL::Cipher::Cipher, OpenSSL::Cipher::Cipher.new(name))
        rescue OpenSSL::Cipher::CipherError => e
          next if /wrap/ =~ name and e.message == 'wrap mode not allowed'
          raise
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
  end

  if has_ciphers?(['aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm'])

    def test_authenticated
      cipher = OpenSSL::Cipher.new('aes-128-gcm')
      assert(cipher.authenticated?)
      cipher = OpenSSL::Cipher.new('aes-128-cbc')
      refute(cipher.authenticated?)
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

  end

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
