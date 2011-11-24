require_relative 'utils'

class OpenSSL::TestEngine < Test::Unit::TestCase

  def test_engines_free # [ruby-dev:44173]
    OpenSSL::Engine.load
    OpenSSL::Engine.engines
    OpenSSL::Engine.engines
    OpenSSL::Engine.cleanup # [ruby-core:40669]
  end

  def test_openssl_engine_builtin
    engine = OpenSSL::Engine.load("openssl")
    assert_equal(true, engine)
    assert_equal(1, OpenSSL::Engine.engines.size)
    cleanup
  end

  def test_openssl_engine_by_id_string
    engine = OpenSSL::Engine.by_id("openssl")
    assert_not_nil(engine)
    assert_equal(1, OpenSSL::Engine.engines.size)
    cleanup
  end

  def test_openssl_engine_id_name_inspect
    engine = OpenSSL::Engine.by_id("openssl")
    assert_equal("openssl", engine.id)
    assert_not_nil(engine.name)
    assert_not_nil(engine.inspect)
    cleanup
  end

  def test_openssl_engine_digest_sha1
    engine = OpenSSL::Engine.by_id("openssl")
    digest = engine.digest("SHA1")
    assert_not_nil(digest)
    data = "test"
    assert_equal(OpenSSL::Digest::SHA1.digest(data), digest.digest(data))
    cleanup
  end

  def test_openssl_engine_cipher_rc4
    engine = OpenSSL::Engine.by_id("openssl")
    algo = "RC4" #AES is not supported by openssl Engine (<=1.0.0e)
    data = "a" * 1000
    key = OpenSSL::Random.random_bytes(16)
    # suppress message from openssl Engine's RC4 cipher [ruby-core:41026]
    err_back = $stderr.dup
    $stderr.reopen(IO::NULL)
    encrypted = crypt_data(data, key, :encrypt) { engine.cipher(algo) }
    decrypted = crypt_data(encrypted, key, :decrypt) { OpenSSL::Cipher.new(algo) }
    assert_equal(data, decrypted)
    cleanup
  ensure
    if err_back
      $stderr.reopen(err_back)
      err_back.close
    end
  end 

  private

  def crypt_data(data, key, mode)
    cipher = yield
    cipher.send mode
    cipher.key = key
    cipher.update(data) + cipher.final
  end

  def cleanup
    OpenSSL::Engine.cleanup
    assert_equal(0, OpenSSL::Engine.engines.size)
  end

end if defined?(OpenSSL)

