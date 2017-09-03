# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestFIPS < OpenSSL::TestCase
  def test_fips_mode_is_reentrant
    OpenSSL.fips_mode = false
    OpenSSL.fips_mode = false
  end

  def test_fips_mode_get
    if OpenSSL::OPENSSL_FIPS
      OpenSSL.fips_mode = true
      assert OpenSSL.fips_mode == true, ".fips_mode returns true when .fips_mode=true"

      OpenSSL.fips_mode = false
      assert OpenSSL.fips_mode == false, ".fips_mode returns false when .fips_mode=false"
    end
  end
end

end
