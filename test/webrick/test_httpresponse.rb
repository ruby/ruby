# frozen_string_literal: false
require "webrick"
require "minitest/autorun"
require "stringio"
require "net/http"

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

    def test_prevent_response_splitting_headers_crlf
      res['X-header'] = "malicious\r\nCookie: hack"
      io = StringIO.new
      res.send_response io
      io.rewind
      res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
      assert_equal '500', res.code
      refute_match 'hack', io.string
    end

    def test_prevent_response_splitting_cookie_headers_crlf
      user_input = "malicious\r\nCookie: hack"
      res.cookies << WEBrick::Cookie.new('author', user_input)
      io = StringIO.new
      res.send_response io
      io.rewind
      res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
      assert_equal '500', res.code
      refute_match 'hack', io.string
    end

    def test_prevent_response_splitting_headers_cr
      res['X-header'] = "malicious\rCookie: hack"
      io = StringIO.new
      res.send_response io
      io.rewind
      res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
      assert_equal '500', res.code
      refute_match 'hack', io.string
    end

    def test_prevent_response_splitting_cookie_headers_cr
      user_input = "malicious\rCookie: hack"
      res.cookies << WEBrick::Cookie.new('author', user_input)
      io = StringIO.new
      res.send_response io
      io.rewind
      res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
      assert_equal '500', res.code
      refute_match 'hack', io.string
    end

    def test_prevent_response_splitting_headers_lf
      res['X-header'] = "malicious\nCookie: hack"
      io = StringIO.new
      res.send_response io
      io.rewind
      res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
      assert_equal '500', res.code
      refute_match 'hack', io.string
    end

    def test_prevent_response_splitting_cookie_headers_lf
      user_input = "malicious\nCookie: hack"
      res.cookies << WEBrick::Cookie.new('author', user_input)
      io = StringIO.new
      res.send_response io
      io.rewind
      res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
      assert_equal '500', res.code
      refute_match 'hack', io.string
    end

    def test_set_redirect_response_splitting
      url = "malicious\r\nCookie: hack"
      assert_raises(URI::InvalidURIError) do
        res.set_redirect(WEBrick::HTTPStatus::MultipleChoices, url)
      end
    end

    def test_set_redirect_html_injection
      url = 'http://example.com////?a</a><head></head><body><img src=1></body>'
      assert_raises(WEBrick::HTTPStatus::MultipleChoices) do
        res.set_redirect(WEBrick::HTTPStatus::MultipleChoices, url)
      end
      res.status = 300
      io = StringIO.new
      res.send_response(io)
      io.rewind
      res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
      assert_equal '300', res.code
      refute_match(/<img/, io.string)
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

    def test_200_chunked_does_not_set_content_length
      res.chunked     = false
      res["Transfer-Encoding"] = 'chunked'
      res.setup_header
      assert_nil res.header.fetch('content-length', nil)
    end

    def test_send_body_io
      IO.pipe {|body_r, body_w|
        body_w.write 'hello'
        body_w.close

        @res.body = body_r

        IO.pipe {|r, w|

          @res.send_body w

          w.close

          assert_equal 'hello', r.read
        }
      }
      assert_equal 0, logger.messages.length
    end

    def test_send_body_string
      @res.body = 'hello'

      IO.pipe {|r, w|
        @res.send_body w

        w.close

        assert_equal 'hello', r.read
      }
      assert_equal 0, logger.messages.length
    end

    def test_send_body_string_io
      @res.body = StringIO.new 'hello'

      IO.pipe {|r, w|
        @res.send_body w

        w.close

        assert_equal 'hello', r.read
      }
      assert_equal 0, logger.messages.length
    end

    def test_send_body_io_chunked
      @res.chunked = true

      IO.pipe {|body_r, body_w|

        body_w.write 'hello'
        body_w.close

        @res.body = body_r

        IO.pipe {|r, w|
          @res.send_body w

          w.close

          r.binmode
          assert_equal "5\r\nhello\r\n0\r\n\r\n", r.read
        }
      }
      assert_equal 0, logger.messages.length
    end

    def test_send_body_string_chunked
      @res.chunked = true

      @res.body = 'hello'

      IO.pipe {|r, w|
        @res.send_body w

        w.close

        r.binmode
        assert_equal "5\r\nhello\r\n0\r\n\r\n", r.read
      }
      assert_equal 0, logger.messages.length
    end

    def test_send_body_string_io_chunked
      @res.chunked = true

      @res.body = StringIO.new 'hello'

      IO.pipe {|r, w|
        @res.send_body w

        w.close

        r.binmode
        assert_equal "5\r\nhello\r\n0\r\n\r\n", r.read
      }
      assert_equal 0, logger.messages.length
    end

    def test_send_body_proc
      @res.body = Proc.new { |out| out.write('hello') }
      IO.pipe do |r, w|
        @res.send_body(w)
        w.close
        r.binmode
        assert_equal 'hello', r.read
      end
      assert_equal 0, logger.messages.length
    end

    def test_send_body_proc_chunked
      @res.body = Proc.new { |out| out.write('hello') }
      @res.chunked = true
      IO.pipe do |r, w|
        @res.send_body(w)
        w.close
        r.binmode
        assert_equal "5\r\nhello\r\n0\r\n\r\n", r.read
      end
      assert_equal 0, logger.messages.length
    end

    def test_set_error
      status = 400
      message = 'missing attribute'
      @res.status = status
      error = WEBrick::HTTPStatus[status].new(message)
      body = @res.set_error(error)
      assert_match(/#{@res.reason_phrase}/, body)
      assert_match(/#{message}/, body)
    end

    def test_no_extraneous_space
      [200, 300, 400, 500].each do |status|
        @res.status = status
        assert_match(/\S\r\n/, @res.status_line)
      end
    end
  end
end
