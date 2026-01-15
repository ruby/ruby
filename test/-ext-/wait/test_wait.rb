# frozen_string_literal: false
require 'test/unit'

class TestWait < Test::Unit::TestCase
  require '-test-/wait'

  def test_wait_for_valid_fd
    IO.pipe do |r,w|
      rc = IO.io_wait(w, IO::WRITABLE, nil)
      assert_equal IO::WRITABLE, rc
    end
  end

  def test_wait_for_invalid_fd
    assert_separately [], <<~'RUBY'
      require '-test-/wait'

      r, w = IO.pipe
      r.close

      IO.for_fd(w.fileno).close

      assert_raise(Errno::EBADF) do
        IO.io_wait(w, IO::WRITABLE, nil)
      end
    RUBY
  end

  def test_wait_for_closed_pipe
    IO.pipe do |r,w|
      w.close
      rc = IO.io_wait(r, IO::READABLE, nil)
      assert_equal IO::READABLE, rc
    end
  end
end
