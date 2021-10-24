# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestFIPS < OpenSSL::TestCase
  def test_fips_mode_is_reentrant
    OpenSSL.fips_mode = false
    OpenSSL.fips_mode = false
  end

  def test_fips_mode_get
    return unless OpenSSL::OPENSSL_FIPS
    assert_separately([{ "OSSL_MDEBUG" => nil }, "-ropenssl"], <<~"end;")
      require #{__FILE__.dump}

      begin
        OpenSSL.fips_mode = true
        assert OpenSSL.fips_mode == true, ".fips_mode returns true when .fips_mode=true"

        OpenSSL.fips_mode = false
        assert OpenSSL.fips_mode == false, ".fips_mode returns false when .fips_mode=false"
      rescue OpenSSL::OpenSSLError
        pend "Could not set FIPS mode (OpenSSL::OpenSSLError: \#$!); skipping"
      end
    end;
  end
end

end
