# frozen_string_literal: true
require 'test/unit'
require '-test-/thread_fd'

class TestThreadFdClose < Test::Unit::TestCase

  def test_thread_fd_close
    omit 'delete this test - we removed the implementation of rb_io_thread_close'
    IO.pipe do |r, w|
      th = Thread.new do
        begin
          assert_raise(IOError) {
            r.read(4)
          }
        ensure
          w.syswrite('done')
        end
      end
      Thread.pass until th.stop?
      IO.thread_fd_close(r.fileno)
      assert_equal 'done', r.read(4)
      th.join
    end
  end
end
