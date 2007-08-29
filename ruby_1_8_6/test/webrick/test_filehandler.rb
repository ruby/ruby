require "test/unit"
require "webrick"
require "stringio"

class WEBrick::TestFileHandler < Test::Unit::TestCase
  def default_file_handler(filename)
    klass = WEBrick::HTTPServlet::DefaultFileHandler
    klass.new(WEBrick::Config::HTTP, filename)
  end

  def get_res_body(res)
    return res.body.read rescue res.body
  end

  def make_range_request(range_spec)
    msg = <<-_end_of_request_
      GET / HTTP/1.0
      Range: #{range_spec}

    _end_of_request_
    return StringIO.new(msg.gsub(/^ {6}/, ""))
  end

  def make_range_response(file, range_spec)
    req = WEBrick::HTTPRequest.new(WEBrick::Config::HTTP)
    req.parse(make_range_request(range_spec))
    res = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
    size = File.size(file)
    handler = default_file_handler(file)
    handler.make_partial_content(req, res, file, size)
    return res
  end

  def test_make_partial_content
    filename = __FILE__
    filesize = File.size(filename)

    res = make_range_response(filename, "bytes=#{filesize-100}-")
    assert_match(%r{^text/plain}, res["content-type"])
    assert_equal(get_res_body(res).size, 100)

    res = make_range_response(filename, "bytes=-100")
    assert_match(%r{^text/plain}, res["content-type"])
    assert_equal(get_res_body(res).size, 100)

    res = make_range_response(filename, "bytes=0-99")
    assert_match(%r{^text/plain}, res["content-type"])
    assert_equal(get_res_body(res).size, 100)

    res = make_range_response(filename, "bytes=100-199")
    assert_match(%r{^text/plain}, res["content-type"])
    assert_equal(get_res_body(res).size, 100)

    res = make_range_response(filename, "bytes=0-0")
    assert_match(%r{^text/plain}, res["content-type"])
    assert_equal(get_res_body(res).size, 1)

    res = make_range_response(filename, "bytes=-1")
    assert_match(%r{^text/plain}, res["content-type"])
    assert_equal(get_res_body(res).size, 1)

    res = make_range_response(filename, "bytes=0-0, -2")
    assert_match(%r{^multipart/byteranges}, res["content-type"])
  end
end
