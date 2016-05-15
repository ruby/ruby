# frozen_string_literal: false
require 'test/unit'
require 'drb/drb'
require 'drb/timeridconv'

require 'thread'

module DRbTests

class TestDRbTimerIdConv < Test::Unit::TestCase
  def test_shutdown_kills_timer_thread
    threads_before = Thread.list.select(&:alive?)
    timer = DRb::TimerIdConv.new

    threads_after = Thread.list.select(&:alive?)
    assert_equal(1, threads_after.length - threads_before.length)

    timer.shutdown
    threads_after = Thread.list.select(&:alive?)
    assert_equal(0, threads_after.length - threads_before.length)
  end
end
end
