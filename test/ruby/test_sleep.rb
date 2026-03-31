# frozen_string_literal: false
require 'test/unit'
require 'etc'
require 'timeout'

class TestSleep < Test::Unit::TestCase
  def test_sleep_5sec
    EnvUtil.without_gc do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep 5
      slept = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      bottom = 5.0
      assert_operator(slept, :>=, bottom)
      assert_operator(slept, :<=, 6.0, "[ruby-core:18015]: longer than expected")
    end
  end

  def test_sleep_forever_not_woken_by_sigchld
    begin
      t = Thread.new do
        sleep 0.5
        `echo hello`
      end

      assert_raise Timeout::Error do
        Timeout.timeout 2 do
          sleep # Should block forever
        end
      end
    ensure
      t.join
    end
  end
end
