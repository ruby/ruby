# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestFIPS < OpenSSL::TestCase
  def test_fips_mode_get_is_true_on_fips_mode_enabled
    unless ENV["TEST_RUBY_OPENSSL_FIPS_ENABLED"]
      omit "Only for FIPS mode environment"
    end

    assert_separately(["-ropenssl"], <<~"end;")
      assert OpenSSL.fips_mode == true, ".fips_mode should return true on FIPS mode enabled"
    end;
  end

  def test_fips_mode_get_is_false_on_fips_mode_disabled
    if ENV["TEST_RUBY_OPENSSL_FIPS_ENABLED"]
      omit "Only for non-FIPS mode environment"
    end

    assert_separately(["-ropenssl"], <<~"end;")
      message = ".fips_mode should return false on FIPS mode disabled. " \
                "If you run the test on FIPS mode, please set " \
                "TEST_RUBY_OPENSSL_FIPS_ENABLED=true"
      assert OpenSSL.fips_mode == false, message
    end;
  end

  def test_fips_mode_is_reentrant
    assert_separately(["-ropenssl"], <<~"end;")
      OpenSSL.fips_mode = false
      OpenSSL.fips_mode = false
    end;
  end

  def test_fips_mode_get_with_fips_mode_set
    omit('OpenSSL is not FIPS-capable') unless OpenSSL::OPENSSL_FIPS

    assert_separately(["-ropenssl"], <<~"end;")
      begin
        OpenSSL.fips_mode = true
        assert OpenSSL.fips_mode == true, ".fips_mode should return true when .fips_mode=true"

        OpenSSL.fips_mode = false
        assert OpenSSL.fips_mode == false, ".fips_mode should return false when .fips_mode=false"
      rescue OpenSSL::OpenSSLError
        pend "Could not set FIPS mode (OpenSSL::OpenSSLError: \#$!); skipping"
      end
    end;
  end
end

end
