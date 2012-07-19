require 'net/http'
require 'test/unit'
require 'stringio'

class HTTPRequestTest < Test::Unit::TestCase

  def test_initialize_GET
    req = Net::HTTP::Get.new '/'

    assert_equal 'GET', req.method
    refute req.request_body_permitted?
    assert req.response_body_permitted?

    expected = {
      'accept'     => %w[*/*],
      'user-agent' => %w[Ruby],
    }

    expected['accept-encoding'] = %w[gzip;q=1.0,deflate;q=0.6,identity;q=0.3] if
      Net::HTTP::HAVE_ZLIB

    assert_equal expected, req.to_hash
  end

  def test_initialize_GET_range
    req = Net::HTTP::Get.new '/', 'Range' => 'bytes=0-9'

    assert_equal 'GET', req.method
    refute req.request_body_permitted?
    assert req.response_body_permitted?

    expected = {
      'accept'     => %w[*/*],
      'user-agent' => %w[Ruby],
      'range'      => %w[bytes=0-9],
    }

    assert_equal expected, req.to_hash
  end

  def test_initialize_HEAD
    req = Net::HTTP::Head.new '/'

    assert_equal 'HEAD', req.method
    refute req.request_body_permitted?
    refute req.response_body_permitted?

    expected = {
      'accept'     => %w[*/*],
      'user-agent' => %w[Ruby],
    }

    assert_equal expected, req.to_hash
  end

end

