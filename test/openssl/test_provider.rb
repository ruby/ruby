# frozen_string_literal: true
require_relative 'utils'
if defined?(OpenSSL) && defined?(OpenSSL::Provider) && !OpenSSL.fips_mode

class OpenSSL::TestProvider < OpenSSL::TestCase
  def test_openssl_provider_name_inspect
    with_openssl <<-'end;'
      provider = OpenSSL::Provider.load("default")
      assert_equal("default", provider.name)
      assert_not_nil(provider.inspect)
    end;
  end

  def test_openssl_provider_names
    with_openssl <<-'end;'
      base_provider = OpenSSL::Provider.load("base")
      assert_equal(2, OpenSSL::Provider.provider_names.size)
      assert_includes(OpenSSL::Provider.provider_names, "base")

      assert_equal(true, base_provider.unload)
      assert_equal(1, OpenSSL::Provider.provider_names.size)
      assert_not_includes(OpenSSL::Provider.provider_names, "base")
    end;
  end

  def test_unloaded_openssl_provider
    with_openssl <<-'end;'
      default_provider = OpenSSL::Provider.load("default")
      assert_equal(true, default_provider.unload)
      assert_raise(OpenSSL::Provider::ProviderError) { default_provider.name }
      assert_raise(OpenSSL::Provider::ProviderError) { default_provider.unload }
    end;
  end

  def test_openssl_legacy_provider
    with_openssl(<<-'end;')
      begin
        OpenSSL::Provider.load("legacy")
      rescue OpenSSL::Provider::ProviderError
        omit "Only for OpenSSL with legacy provider"
      end

      algo = "RC4"
      data = "a" * 1000
      key = OpenSSL::Random.random_bytes(16)

      # default provider does not support RC4
      cipher = OpenSSL::Cipher.new(algo)
      cipher.encrypt
      cipher.key = key
      encrypted = cipher.update(data) + cipher.final

      other_cipher = OpenSSL::Cipher.new(algo)
      other_cipher.decrypt
      other_cipher.key = key
      decrypted = other_cipher.update(encrypted) + other_cipher.final

      assert_equal(data, decrypted)
    end;
  end

  private

  # this is required because OpenSSL::Provider methods change global state
  def with_openssl(code, **opts)
    assert_separately(["-ropenssl"], <<~"end;", **opts)
      #{code}
    end;
  end
end

end
