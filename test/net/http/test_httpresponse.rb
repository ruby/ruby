# coding: US-ASCII
# frozen_string_literal: false
require 'net/http'
require 'test/unit'
require 'stringio'

class HTTPResponseTest < Test::Unit::TestCase
  def test_singleline_header
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Content-Length: 5
Connection: close

hello
EOS
    res = Net::HTTPResponse.read_new(io)
    assert_equal('5', res['content-length'])
    assert_equal('close', res['connection'])
  end

  def test_multiline_header
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
X-Foo: XXX
   YYY
X-Bar:
 XXX
\tYYY

hello
EOS
    res = Net::HTTPResponse.read_new(io)
    assert_equal('XXX YYY', res['x-foo'])
    assert_equal('XXX YYY', res['x-bar'])
  end

  def test_read_body
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Length: 5

hello
EOS

    res = Net::HTTPResponse.read_new(io)

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    assert_equal 'hello', body
  end

  def test_read_body_block
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Length: 5

hello
EOS

    res = Net::HTTPResponse.read_new(io)

    body = ''

    res.reading_body io, true do
      res.read_body do |chunk|
        body << chunk
      end
    end

    assert_equal 'hello', body
  end

  def test_read_body_content_encoding_deflate
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Encoding: deflate
Content-Length: 13

x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15
EOS

    res = Net::HTTPResponse.read_new(io)
    res.decode_content = true

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    if Net::HTTP::HAVE_ZLIB
      assert_equal nil, res['content-encoding']
      assert_equal 'hello', body
    else
      assert_equal 'deflate', res['content-encoding']
      assert_equal "x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15", body
    end
  end

  def test_read_body_content_encoding_deflate_uppercase
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Encoding: DEFLATE
Content-Length: 13

x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15
EOS

    res = Net::HTTPResponse.read_new(io)
    res.decode_content = true

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    if Net::HTTP::HAVE_ZLIB
      assert_equal nil, res['content-encoding']
      assert_equal 'hello', body
    else
      assert_equal 'DEFLATE', res['content-encoding']
      assert_equal "x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15", body
    end
  end

  def test_read_body_content_encoding_deflate_chunked
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Encoding: deflate
Transfer-Encoding: chunked

6
x\x9C\xCBH\xCD\xC9
7
\xC9\a\x00\x06,\x02\x15
0

EOS

    res = Net::HTTPResponse.read_new(io)
    res.decode_content = true

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    if Net::HTTP::HAVE_ZLIB
      assert_equal nil, res['content-encoding']
      assert_equal 'hello', body
    else
      assert_equal 'deflate', res['content-encoding']
      assert_equal "x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15", body
    end
  end

  def test_read_body_content_encoding_deflate_disabled
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Encoding: deflate
Content-Length: 13

x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15
EOS

    res = Net::HTTPResponse.read_new(io)
    res.decode_content = false # user set accept-encoding in request

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    assert_equal 'deflate', res['content-encoding'], 'Bug #7831'
    assert_equal "x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15", body, 'Bug #7381'
  end

  def test_read_body_content_encoding_deflate_no_length
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Encoding: deflate

x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15
EOS

    res = Net::HTTPResponse.read_new(io)
    res.decode_content = true

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    if Net::HTTP::HAVE_ZLIB
      assert_equal nil, res['content-encoding']
      assert_equal 'hello', body
    else
      assert_equal 'deflate', res['content-encoding']
      assert_equal "x\x9C\xCBH\xCD\xC9\xC9\a\x00\x06,\x02\x15\r\n", body
    end
  end

  def test_read_body_content_encoding_deflate_content_range
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Accept-Ranges: bytes
Connection: close
Content-Encoding: gzip
Content-Length: 10
Content-Range: bytes 0-9/55

\x1F\x8B\b\x00\x00\x00\x00\x00\x00\x03
EOS

    res = Net::HTTPResponse.read_new(io)

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    assert_equal "\x1F\x8B\b\x00\x00\x00\x00\x00\x00\x03", body
  end

  def test_read_body_content_encoding_deflate_empty_body
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Encoding: deflate
Content-Length: 0

EOS

    res = Net::HTTPResponse.read_new(io)
    res.decode_content = true

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    if Net::HTTP::HAVE_ZLIB
      assert_equal nil, res['content-encoding']
      assert_equal '', body
    else
      assert_equal 'deflate', res['content-encoding']
      assert_equal '', body
    end
  end

  def test_read_body_content_encoding_deflate_empty_body_no_length
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Encoding: deflate

EOS

    res = Net::HTTPResponse.read_new(io)
    res.decode_content = true

    body = nil

    res.reading_body io, true do
      body = res.read_body
    end

    if Net::HTTP::HAVE_ZLIB
      assert_equal nil, res['content-encoding']
      assert_equal '', body
    else
      assert_equal 'deflate', res['content-encoding']
      assert_equal '', body
    end
  end

  def test_read_body_string
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Connection: close
Content-Length: 5

hello
EOS

    res = Net::HTTPResponse.read_new(io)

    body = ''

    res.reading_body io, true do
      res.read_body body
    end

    assert_equal 'hello', body
  end

  def test_uri_equals
    uri = URI 'http://example'

    response = Net::HTTPResponse.new '1.1', 200, 'OK'

    response.uri = nil

    assert_nil response.uri

    response.uri = uri

    assert_equal uri, response.uri
    assert_not_same  uri, response.uri
  end

  def test_ensure_zero_space_does_not_regress
    io = dummy_io(<<EOS)
HTTP/1.1 200OK
Content-Length: 5
Connection: close

hello
EOS

    assert_raise Net::HTTPBadResponse do
      Net::HTTPResponse.read_new(io)
    end
  end

  def test_allow_trailing_space_after_status
    io = dummy_io(<<EOS)
HTTP/1.1 200\s
Content-Length: 5
Connection: close

hello
EOS

    res = Net::HTTPResponse.read_new(io)
    assert_equal('1.1', res.http_version)
    assert_equal('200', res.code)
    assert_equal('', res.message)
  end

  def test_normal_status_line
    io = dummy_io(<<EOS)
HTTP/1.1 200 OK
Content-Length: 5
Connection: close

hello
EOS

    res = Net::HTTPResponse.read_new(io)
    assert_equal('1.1', res.http_version)
    assert_equal('200', res.code)
    assert_equal('OK', res.message)
  end

  def test_allow_empty_reason_code
    io = dummy_io(<<EOS)
HTTP/1.1 200
Content-Length: 5
Connection: close

hello
EOS

    res = Net::HTTPResponse.read_new(io)
    assert_equal('1.1', res.http_version)
    assert_equal('200', res.code)
    assert_equal(nil, res.message)
  end

  def test_raises_exception_with_missing_reason
    io = dummy_io(<<EOS)
HTTP/1.1 404
Content-Length: 5
Connection: close

hello
EOS

    res = Net::HTTPResponse.read_new(io)
    assert_equal(nil, res.message)
    assert_raise Net::HTTPServerException do
      res.error!
    end
  end

private

  def dummy_io(str)
    str = str.gsub(/\n/, "\r\n")

    Net::BufferedIO.new(StringIO.new(str))
  end
end
