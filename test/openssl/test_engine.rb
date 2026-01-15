# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL) && defined?(OpenSSL::Engine)

class OpenSSL::TestEngine < OpenSSL::TestCase
  def test_engines_free # [ruby-dev:44173]
    with_openssl <<-'end;'
      OpenSSL::Engine.load("openssl")
      OpenSSL::Engine.engines
      OpenSSL::Engine.engines
    end;
  end

  def test_openssl_engine_builtin
    with_openssl <<-'end;'
      orig = OpenSSL::Engine.engines
      pend "'openssl' is already loaded" if orig.any? { |e| e.id == "openssl" }
      engine = OpenSSL::Engine.load("openssl")
      assert_equal(true, engine)
      assert_equal(1, OpenSSL::Engine.engines.size - orig.size)
    end;
  end

  def test_openssl_engine_by_id_string
    with_openssl <<-'end;'
      orig = OpenSSL::Engine.engines
      pend "'openssl' is already loaded" if orig.any? { |e| e.id == "openssl" }
      engine = OpenSSL::Engine.by_id("openssl")
      assert_not_nil(engine)
      assert_equal(1, OpenSSL::Engine.engines.size - orig.size)
    end;
  end

  def test_openssl_engine_id_name_inspect
    with_openssl <<-'end;'
      engine = OpenSSL::Engine.by_id("openssl")
      assert_equal("openssl", engine.id)
      assert_not_nil(engine.name)
      assert_not_nil(engine.inspect)
    end;
  end

  def test_openssl_engine_digest_sha1
    with_openssl <<-'end;'
      engine = OpenSSL::Engine.by_id("openssl")
      digest = engine.digest("SHA1")
      assert_not_nil(digest)
      data = "test"
      assert_equal(OpenSSL::Digest.digest('SHA1', data), digest.digest(data))
    end;
  end

  def test_openssl_engine_cipher_rc4
    begin
      OpenSSL::Cipher.new("rc4")
    rescue OpenSSL::Cipher::CipherError
      pend "RC4 is not supported"
    end

    with_openssl(<<-'end;', ignore_stderr: true)
      engine = OpenSSL::Engine.by_id("openssl")
      algo = "RC4"
      data = "a" * 1000
      key = OpenSSL::Random.random_bytes(16)

      cipher = engine.cipher(algo)
      cipher.encrypt
      cipher.key = key
      encrypted = cipher.update(data) + cipher.final

      cipher = OpenSSL::Cipher.new(algo)
      cipher.decrypt
      cipher.key = key
      decrypted = cipher.update(encrypted) + cipher.final

      assert_equal(data, decrypted)
    end;
  end

  private

  # this is required because OpenSSL::Engine methods change global state
  def with_openssl(code, **opts)
    assert_separately(["-ropenssl"], <<~"end;", **opts)
      #{code}
    end;
  end
end

end
