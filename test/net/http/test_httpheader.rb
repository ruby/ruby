require 'net/http'
require 'test/unit'

class HTTPHeaderTest < Test::Unit::TestCase

  class C
    include Net::HTTPHeader
    def initialize
      @header = {}
    end
  end

  def setup
    @c = C.new
  end

  def test_size
    assert_equal 0, @c.size
    @c['a'] = 'a'
    assert_equal 1, @c.size
    @c['b'] = 'b'
    assert_equal 2, @c.size
    @c['b'] = 'b'
    assert_equal 2, @c.size
    @c['c'] = 'c'
    assert_equal 3, @c.size
  end

  def test_ASET
    @c['My-Header'] = 'test string'
    @c['my-Header'] = 'test string'
    @c['My-header'] = 'test string'
    @c['my-header'] = 'test string'
    @c['MY-HEADER'] = 'test string'
    assert_equal 1, @c.size

    @c['AaA'] = 'aaa'
    @c['aaA'] = 'aaa'
    @c['AAa'] = 'aaa'
    assert_equal 2, @c.length
  end

  def test_AREF
    @c['My-Header'] = 'test string'
    assert_equal 'test string', @c['my-header']
    assert_equal 'test string', @c['MY-header']
    assert_equal 'test string', @c['my-HEADER']

    @c['Next-Header'] = 'next string'
    assert_equal 'next string', @c['next-header']
  end

  def test_range
    try_range(1..5,     '1-5')
    try_range(234..567, '234-567')
    try_range(-5..-1,   '-5')
    try_range(1..-1,    '1-')
  end

  def try_range(r, s)
    @c['range'] = "bytes=#{s}"
    ret, = @c.range
    assert_equal r, ret
  end

  def test_range=
    @c.range = 0..499
    assert_equal 'bytes=0-499', @c['range']
    @c.range = 0...500
    assert_equal 'bytes=0-499', @c['range']
    @c.range = 300
    assert_equal 'bytes=0-299', @c['range']
    @c.range = -400
    assert_equal 'bytes=-400', @c['range']
    @c.set_range 0, 500
    assert_equal 'bytes=0-499', @c['range']
  end

  def test_chunked?
    try_chunked true, 'chunked'
    try_chunked true, '  chunked  '
    try_chunked true, '(OK)chunked'

    try_chunked false, 'not-chunked'
    try_chunked false, 'chunked-but-not-chunked'
  end

  def try_chunked(bool, str)
    @c['transfer-encoding'] = str
    assert_equal bool, @c.chunked?
  end

  def test_content_length
    @c.delete('content-length')
    assert_nil @c['content-length']

    try_content_length 500, '500'
    try_content_length 10000_0000_0000, '1000000000000'
    try_content_length 123, '  123'
    try_content_length 1,   '1 23'
    try_content_length 500, '(OK)500'
    assert_raises(Net::HTTPHeaderSyntaxError, 'here is no digit, but') {
      @c['content-length'] = 'no digit'
      @c.content_length
    }
  end

  def try_content_length(len, str)
    @c['content-length'] = str
    assert_equal len, @c.content_length
  end

  def test_content_range
  end

  def test_delete
  end

  def test_each
  end

  def test_each_key
  end

  def test_each_value
  end

  def test_key?
  end

  def test_range_length
  end

  def test_to_hash
  end

end
