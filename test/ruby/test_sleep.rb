# frozen_string_literal: false
require 'test/unit'
require 'etc'

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
end
