begin
  require "openssl"
rescue LoadError
end
require "test/unit"

if defined?(OpenSSL)

class OpenSSL::TestCipher < Test::Unit::TestCase
  def setup
    @c1 = OpenSSL::Cipher::Cipher.new("DES-EDE3-CBC")
    @c2 = OpenSSL::Cipher::DES.new(:EDE3, "CBC")
    @key = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
    @iv = "\0\0\0\0\0\0\0\0"
    @iv1 = "\1\1\1\1\1\1\1\1"
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

  def test_set_iv
    @c1.encrypt
    @c1.key = @key
    @c1.iv = @iv
    s1 = @c1.update(@data) + @c1.final
    @c1.iv = @iv1
    s1 += @c1.update(@data) + @c1.final
    @c1.reset
    @c1.iv = @iv
    s2 = @c1.update(@data) + @c1.final
    @c1.iv = @iv1
    s2 += @c1.update(@data) + @c1.final
    assert_equal(s1, s2, "encrypt reset")
  end

  def test_empty_data
    @c1.encrypt
    assert_raise(ArgumentError){ @c1.update("") }
  end

  def test_disable_padding(padding=0)
    # assume a padding size of 8
    # encrypt the data with padding
    @c1.encrypt
    @c1.key = @key
    @c1.iv = @iv
    encrypted_data = @c1.update(@data) + @c1.final
    assert_equal(8, encrypted_data.size)
    # decrypt with padding disabled
    @c1.decrypt
    @c1.padding = padding
    decrypted_data = @c1.update(encrypted_data) + @c1.final
    # check that the result contains the padding
    assert_equal(8, decrypted_data.size)
    assert_equal(@data, decrypted_data[0...@data.size])
  end

  if RUBY_PLATFORM =~ /java/
    # JRuby extension - using Java padding types

    def test_disable_padding_javastyle
      test_disable_padding('NoPadding')
    end

    def test_iso10126_padding
      @c1.encrypt
      @c1.key = @key
      @c1.iv = @iv
      @c1.padding = 'ISO10126Padding'
      encrypted_data = @c1.update(@data) + @c1.final
      # decrypt with padding disabled to see the padding
      @c1.decrypt
      @c1.padding = 0
      decrypted_data = @c1.update(encrypted_data) + @c1.final
      assert_equal(@data, decrypted_data[0...@data.size])
      # last byte should be the amount of padding
      assert_equal(4, decrypted_data[-1])
    end

    def test_iso10126_padding_boundry
      @data = 'HELODATA' # 8 bytes, same as padding size
      @c1.encrypt
      @c1.key = @key
      @c1.iv = @iv
      @c1.padding = 'ISO10126Padding'
      encrypted_data = @c1.update(@data) + @c1.final
      # decrypt with padding disabled to see the padding
      @c1.decrypt
      @c1.padding = 0
      decrypted_data = @c1.update(encrypted_data) + @c1.final
      assert_equal(@data, decrypted_data[0...@data.size])
      # padding should be one whole block
      assert_equal(8, decrypted_data[-1])
    end
  end

  if OpenSSL::OPENSSL_VERSION_NUMBER > 0x00907000
    def test_ciphers
      OpenSSL::Cipher.ciphers.each{|name|
        assert(OpenSSL::Cipher::Cipher.new(name).is_a?(OpenSSL::Cipher::Cipher))
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
  end

  # JRUBY-4028
  def test_jruby_4028
    key = "0599E113A7EE32A9"
    data = "1234567890~5J96LC303C1D22DD~20090930005944~http%3A%2F%2Flocalhost%3A8080%2Flogin%3B0%3B1~http%3A%2F%2Fmix-stage.oracle.com%2F~00"
    c1 = OpenSSL::Cipher::Cipher.new("DES-CBC")
    c1.padding = 0
    c1.iv = "0" * 8
    c1.encrypt
    c1.key = key
    e = c1.update data
    e << c1.final

    c2 = OpenSSL::Cipher::Cipher.new("DES-CBC")
    c2.padding = 0
    c2.iv = "0" * 8
    c2.decrypt
    c2.key = key
    d = c2.update e
    d << c2.final

    assert_equal "\342\320B.\300&X\310\344\253\025\215\017*\22015\344\024D\342\213\361\336\311\271\326\016\243\214\026\2545\002\237,\017s\202\316&Ew\323\221H\376\200\304\201\365\332Im\240\361\037\246\3536\001A2\341\324o0\350\364%=\325\330\240\324u\225\304h\277\272\361f\024\324\352\336\353N\002/]C\370!\003)\212oa\225\207\333\340\245\207\024\351\037\327[\212\001{\216\f\315\345\372\v\226\r\233?\002\vJK", e
    assert_equal data, d
  end
end

end
