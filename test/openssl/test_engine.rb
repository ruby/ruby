# frozen_string_literal: false
require_relative 'utils'

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
      engine = get_engine
      assert_not_nil(engine)
      assert_equal(1, OpenSSL::Engine.engines.size - orig.size)
    end;
  end

  def test_openssl_engine_id_name_inspect
    with_openssl <<-'end;'
      engine = get_engine
      assert_equal("openssl", engine.id)
      assert_not_nil(engine.name)
      assert_not_nil(engine.inspect)
    end;
  end

  def test_openssl_engine_digest_sha1
    with_openssl <<-'end;'
      engine = get_engine
      digest = engine.digest("SHA1")
      assert_not_nil(digest)
      data = "test"
      assert_equal(OpenSSL::Digest::SHA1.digest(data), digest.digest(data))
    end;
  end

  def test_openssl_engine_cipher_rc4
    with_openssl <<-'end;'
      begin
        engine = get_engine
        algo = "RC4" #AES is not supported by openssl Engine (<=1.0.0e)
        data = "a" * 1000
        key = OpenSSL::Random.random_bytes(16)
        # suppress message from openssl Engine's RC4 cipher [ruby-core:41026]
        err_back = $stderr.dup
        $stderr.reopen(IO::NULL)
        encrypted = crypt_data(data, key, :encrypt) { engine.cipher(algo) }
        decrypted = crypt_data(encrypted, key, :decrypt) { OpenSSL::Cipher.new(algo) }
        assert_equal(data, decrypted)
      ensure
        if err_back
          $stderr.reopen(err_back)
          err_back.close
        end
      end
    end;
  end

  private

  # this is required because OpenSSL::Engine methods change global state
  def with_openssl(code)
    assert_separately([{ "OSSL_MDEBUG" => nil }, "-ropenssl"], <<~"end;")
      require #{__FILE__.dump}
      include OpenSSL::TestEngine::Utils
      #{code}
    end;
  end

  module Utils
    def get_engine
      OpenSSL::Engine.by_id("openssl")
    end

    def crypt_data(data, key, mode)
      cipher = yield
      cipher.send mode
      cipher.key = key
      cipher.update(data) + cipher.final
    end
  end

end if defined?(OpenSSL::TestUtils) && defined?(OpenSSL::Engine)
