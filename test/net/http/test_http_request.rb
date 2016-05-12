# frozen_string_literal: false
require 'net/http'
require 'test/unit'
require 'stringio'

class HTTPRequestTest < Test::Unit::TestCase

  def test_initialize_GET
    req = Net::HTTP::Get.new '/'

    assert_equal 'GET', req.method
    assert_not_predicate req, :request_body_permitted?
    assert_predicate req, :response_body_permitted?

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
    assert_not_predicate req, :request_body_permitted?
    assert_predicate req, :response_body_permitted?

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
    assert_not_predicate req, :request_body_permitted?
    assert_not_predicate req, :response_body_permitted?

    expected = {
      'accept'     => %w[*/*],
      'user-agent' => %w[Ruby],
    }

    assert_equal expected, req.to_hash
  end

  def test_initialize_accept_encoding
    req1 = Net::HTTP::Get.new '/'

    assert req1.decode_content, 'Bug #7831 - automatically decode content'

    req2 = Net::HTTP::Get.new '/', 'accept-encoding' => 'identity'

    assert_not_predicate req2, :decode_content,
                         'Bug #7381 - do not decode content if the user overrides'
  end if Net::HTTP::HAVE_ZLIB

  def test_header_set
    req = Net::HTTP::Get.new '/'

    assert req.decode_content, 'Bug #7831 - automatically decode content'

    req['accept-encoding'] = 'identity'

    assert_not_predicate req, :decode_content,
                         'Bug #7831 - do not decode content if the user overrides'
  end if Net::HTTP::HAVE_ZLIB

end

