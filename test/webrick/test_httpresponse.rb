require "webrick"
require "minitest/autorun"
require "stringio"

module WEBrick
  class TestHTTPResponse < MiniTest::Unit::TestCase
    class FakeLogger
      attr_reader :messages

      def initialize
        @messages = []
      end

      def warn msg
        @messages << msg
      end
    end

    attr_reader :config, :logger, :res

    def setup
      super
      @logger          = FakeLogger.new
      @config          = Config::HTTP
      @config[:Logger] = logger
      @res             = HTTPResponse.new config
      @res.keep_alive  = true
    end

    def test_304_does_not_log_warning
      res.status      = 304
      res.setup_header
      assert_equal 0, logger.messages.length
    end

    def test_204_does_not_log_warning
      res.status      = 204
      res.setup_header

      assert_equal 0, logger.messages.length
    end

    def test_1xx_does_not_log_warnings
      res.status      = 105
      res.setup_header

      assert_equal 0, logger.messages.length
    end

    def test_send_body_io
      body_r, body_w = IO.pipe

      body_w.write 'hello'
      body_w.close

      @res.body = body_r

      r, w = IO.pipe

      @res.send_body w

      w.close

      assert_equal 'hello', r.read
    end

    def test_send_body_string
      @res.body = 'hello'

      r, w = IO.pipe

      @res.send_body w

      w.close

      assert_equal 'hello', r.read
    end

    def test_send_body_string_io
      @res.body = StringIO.new 'hello'

      r, w = IO.pipe

      @res.send_body w

      w.close

      assert_equal 'hello', r.read
    end

    def test_send_body_io_chunked
      @res.chunked = true

      body_r, body_w = IO.pipe

      body_w.write 'hello'
      body_w.close

      @res.body = body_r

      r, w = IO.pipe

      @res.send_body w

      w.close

      r.binmode
      assert_equal "5\r\nhello\r\n0\r\n\r\n", r.read
    end

    def test_send_body_string_chunked
      @res.chunked = true

      @res.body = 'hello'

      r, w = IO.pipe

      @res.send_body w

      w.close

      r.binmode
      assert_equal "5\r\nhello\r\n0\r\n\r\n", r.read
    end

    def test_send_body_string_io_chunked
      @res.chunked = true

      @res.body = StringIO.new 'hello'

      r, w = IO.pipe

      @res.send_body w

      w.close

      r.binmode
      assert_equal "5\r\nhello\r\n0\r\n\r\n", r.read
    end
  end
end
