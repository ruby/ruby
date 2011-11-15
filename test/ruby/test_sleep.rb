require 'test/unit'

class TestSleep < Test::Unit::TestCase
  def test_sleep_5sec
    GC.disable
    start = Time.now
    sleep 5
    slept = Time.now-start
    assert_operator(5.0, :<=, slept)
    assert_operator(slept, :<=, 6.0, "[ruby-core:18015]: longer than expected")
  ensure
    GC.enable
  end
end
