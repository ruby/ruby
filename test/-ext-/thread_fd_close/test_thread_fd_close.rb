# frozen_string_literal: true
require 'test/unit'
require '-test-/thread_fd_close'
require 'io/wait'

class TestThreadFdClose < Test::Unit::TestCase

  def test_thread_fd_close
    IO.pipe do |r, w|
      th = Thread.new do
        begin
          r.read(4)
        ensure
          w.syswrite('done')
        end
      end
      Thread.pass until th.stop?
      IO.thread_fd_close(r.fileno)
      assert_equal 'done', r.read(4)
      assert_raise(IOError) { th.join }
    end
  end
end
