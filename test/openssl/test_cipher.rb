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
    @iv = @key
    @hexkey = "0000000000000000000000000000000000000000000000"
    @hexiv = "0000000000000000"
    @data = "DATA"
  end

  def teardown
    @c1 = @c2 = nil
  end

  def test_crypt
    s1 = @c1.encrypt(@key, @iv).update(@data) + @c1.final
    s2 = @c2.encrypt(@key, @iv).update(@data) + @c2.final
    assert_equal(s1, s2, "encrypt")
    assert_equal(@data, @c1.decrypt(@key, @iv).update(s2)+@c1.final, "decrypt")
    assert_equal(@data, @c2.decrypt(@key, @iv).update(s1)+@c2.final, "decrypt")
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
end

end
