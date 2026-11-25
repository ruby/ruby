# frozen_string_literal: false
require 'net/http'
require 'stringio'
require 'test/unit'

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
      'accept'          => %w[*/*],
      "accept-encoding" => %w[gzip;q=1.0,deflate;q=0.6,identity;q=0.3],
      'user-agent'      => %w[Ruby],
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

  def test_initialize_GET_uri
    req = Net::HTTP::Get.new(URI("http://example.com/foo"))
    assert_equal "/foo", req.path
    assert_equal "example.com", req['Host']

    req = Net::HTTP::Get.new(URI("https://example.com/foo"))
    assert_equal "/foo", req.path
    assert_equal "example.com", req['Host']

    req = Net::HTTP::Get.new(URI("https://203.0.113.1/foo"))
    assert_equal "/foo", req.path
    assert_equal "203.0.113.1", req['Host']

    req = Net::HTTP::Get.new(URI("https://203.0.113.1:8000/foo"))
    assert_equal "/foo", req.path
    assert_equal "203.0.113.1:8000", req['Host']

    req = Net::HTTP::Get.new(URI("https://[2001:db8::1]:8000/foo"))
    assert_equal "/foo", req.path
    assert_equal "[2001:db8::1]:8000", req['Host']

    assert_raise(ArgumentError){ Net::HTTP::Get.new(URI("urn:ietf:rfc:7231")) }
    assert_raise(ArgumentError){ Net::HTTP::Get.new(URI("http://")) }
  end

  def test_header_set
    req = Net::HTTP::Get.new '/'

    assert req.decode_content, 'Bug #7831 - automatically decode content'

    req['accept-encoding'] = 'identity'

    assert_not_predicate req, :decode_content,
                         'Bug #7831 - do not decode content if the user overrides'
  end if Net::HTTP::HAVE_ZLIB

  def test_update_uri
    req = Net::HTTP::Get.new(URI.parse("http://203.0.113.1"))
    req.update_uri("test", 8080, false)
    assert_equal "203.0.113.1", req.uri.host
    assert_equal 8080, req.uri.port

    req = Net::HTTP::Get.new(URI.parse("http://203.0.113.1:2020"))
    req.update_uri("test", 8080, false)
    assert_equal "203.0.113.1", req.uri.host
    assert_equal 8080, req.uri.port

    req = Net::HTTP::Get.new(URI.parse("http://[2001:db8::1]"))
    req.update_uri("test", 8080, false)
    assert_equal "[2001:db8::1]", req.uri.host
    assert_equal 8080, req.uri.port

    req = Net::HTTP::Get.new(URI.parse("http://[2001:db8::1]:2020"))
    req.update_uri("test", 8080, false)
    assert_equal "[2001:db8::1]", req.uri.host
    assert_equal 8080, req.uri.port
  end

  def test_chunked_request_omits_conflicting_content_length
    # RFC 9112 6.1: Transfer-Encoding: chunked and Content-Length must not both be sent on a
    # request -- together they are a request-smuggling primitive. When a caller sets both,
    # Net::HTTP must drop Content-Length and send only the chunked framing.
    req = Net::HTTP::Post.new('/')
    req['Transfer-Encoding'] = 'chunked'
    req.content_length = 3
    req.body_stream = StringIO.new('abc')

    captured = +''
    sock = Object.new
    sock.define_singleton_method(:write) { |*a| a.each { |s| captured << s.to_s }; captured.bytesize }
    sock.define_singleton_method(:continue_timeout) { nil }

    req.exec(sock, '1.1', '/')
    header = captured.split("\r\n\r\n", 2).first

    assert_match(/Transfer-Encoding: chunked/i, header)
    assert_no_match(/Content-Length/i, header)
  end
end
