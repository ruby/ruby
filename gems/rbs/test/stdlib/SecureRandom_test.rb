require_relative "test_helper"
require "securerandom"

class SecureRandomTest < StdlibTest
  target SecureRandom
  library "securerandom"
  using hook.refinement

  def test_alphanumeric
    SecureRandom.alphanumeric
    SecureRandom.alphanumeric(nil)
    SecureRandom.alphanumeric(4)
  end

  def test_base64
    SecureRandom.base64
    SecureRandom.base64(nil)
    SecureRandom.base64(4)
  end

  def test_hex
    SecureRandom.hex
    SecureRandom.hex(nil)
    SecureRandom.hex(3)
  end

  def test_random_bytes
    SecureRandom.random_bytes
    SecureRandom.random_bytes(nil)
    SecureRandom.random_bytes(3)
  end

  def test_random_number
    SecureRandom.random_number
    SecureRandom.random_number(nil)
    SecureRandom.random_number(0)
    SecureRandom.random_number(4)
  end

  def test_urlsafe_base64
    SecureRandom.urlsafe_base64
    SecureRandom.urlsafe_base64(nil, true)
    SecureRandom.urlsafe_base64(24, false)
  end

  def test_uuid
    SecureRandom.uuid
  end
end
