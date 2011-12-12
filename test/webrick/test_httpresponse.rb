require "webrick"
require "minitest/autorun"

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

    def test_304_does_not_log_warning
      logger          = FakeLogger.new
      config          = Config::HTTP
      config[:Logger] = logger

      res             = HTTPResponse.new config
      res.status      = 304
      res.keep_alive  = true

      res.setup_header

      assert_equal 0, logger.messages.length
    end

    def test_204_does_not_log_warning
      logger          = FakeLogger.new
      config          = Config::HTTP
      config[:Logger] = logger

      res             = HTTPResponse.new config
      res.status      = 204
      res.keep_alive  = true

      res.setup_header

      assert_equal 0, logger.messages.length
    end
  end
end
