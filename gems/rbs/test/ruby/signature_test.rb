require "test_helper"

class Ruby::SignatureTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Ruby::Signature::VERSION
  end
end
