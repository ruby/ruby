# coding: US-ASCII
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
    refute_same  uri, response.uri
  end

private

  def dummy_io(str)
    str = str.gsub(/\n/, "\r\n")

    Net::BufferedIO.new(StringIO.new(str))
  end
end
