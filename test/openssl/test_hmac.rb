# frozen_string_literal: false
require_relative 'utils'

class OpenSSL::TestHMAC < OpenSSL::TestCase
  def test_hmac
    # RFC 2202 2. Test Cases for HMAC-MD5
    hmac = OpenSSL::HMAC.new(["0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"].pack("H*"), "MD5")
    hmac.update("Hi There")
    assert_equal ["9294727a3638bb1c13f48ef8158bfc9d"].pack("H*"), hmac.digest
    assert_equal "9294727a3638bb1c13f48ef8158bfc9d", hmac.hexdigest

    # RFC 4231 4.2. Test Case 1
    hmac = OpenSSL::HMAC.new(["0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"].pack("H*"), "SHA224")
    hmac.update("Hi There")
    assert_equal ["896fb1128abbdf196832107cd49df33f47b4b1169912ba4f53684b22"].pack("H*"), hmac.digest
    assert_equal "896fb1128abbdf196832107cd49df33f47b4b1169912ba4f53684b22", hmac.hexdigest
  end

  def test_dup
    h1 = OpenSSL::HMAC.new("KEY", "MD5")
    h1.update("DATA")
    h = h1.dup
    assert_equal(h1.digest, h.digest, "dup digest")
  end

  def test_binary_update
    data = "Lücíllé: Bût... yøü sáîd hé wås âlrîght.\nDr. Físhmån: Yés. Hé's løst hîs léft hånd, sø hé's gøîng tø bé åll rîght"
    hmac = OpenSSL::HMAC.new("qShkcwN92rsM9nHfdnP4ugcVU2iI7iM/trovs01ZWok", "SHA256")
    result = hmac.update(data).hexdigest
    assert_equal "a13984b929a07912e4e21c5720876a8e150d6f67f854437206e7f86547248396", result
  end

  def test_reset_keep_key
    h1 = OpenSSL::HMAC.new("KEY", "MD5")
    first = h1.update("test").hexdigest
    h1.reset
    second = h1.update("test").hexdigest
    assert_equal first, second
  end
end if defined?(OpenSSL::TestUtils)
