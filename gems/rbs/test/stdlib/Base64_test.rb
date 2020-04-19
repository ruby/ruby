require_relative "test_helper"
require "base64"

class Base64Test < StdlibTest
  target Base64
  library "base64"

  using hook.refinement

  include Base64

  def test_encode64_decode64
    Base64.decode64(Base64.encode64(""))
    decode64(encode64(""))
  end

  def test_strict_encode64_strict_decode64
    Base64.strict_decode64(Base64.strict_encode64(""))
    strict_decode64(strict_encode64(""))
  end

  def test_urlsafe_encode64_urlsafe_decode64
    Base64.urlsafe_decode64(Base64.urlsafe_encode64(""))
    urlsafe_decode64(urlsafe_encode64(""))
  end
end
