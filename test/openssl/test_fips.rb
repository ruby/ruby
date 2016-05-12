# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestFIPS < Test::Unit::TestCase

  def test_fips_mode_is_reentrant
    OpenSSL.fips_mode = false
    OpenSSL.fips_mode = false
  end

end

end
