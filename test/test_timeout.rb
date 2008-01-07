require 'test/unit'
require 'timeout'
require 'thread'

class TestTimeout < Test::Unit::TestCase
  def test_queue
    q = Queue.new
    assert_raise(Timeout::Error, "[ruby-dev:32935]") {
      timeout(0.1) { q.pop }
    }
  end
end

