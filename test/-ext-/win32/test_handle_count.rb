# frozen_string_literal: false
require 'test/unit'

module Bug
  module Win32
    class TestHandleCount < Test::Unit::TestCase
      def test_read_nonblock_on_empty_pipe
        require '-test-/win32/handle_count'
        IO.pipe do |r, w|
          r.read_nonblock(1, exception: false)
          before = Bug::Win32.handle_count
          1000.times {r.read_nonblock(1, exception: false)}
          assert_operator(Bug::Win32.handle_count - before, :<, 100)
        end
      end
    end
  end
end if /mswin|mingw/ =~ RUBY_PLATFORM
