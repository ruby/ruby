require 'test/unit'

class TestSleep < Test::Unit::TestCase
  def test_sleep_5sec
    start = Time.now
    sleep 5
    slept = Time.now-start
    assert_in_delta(5.0, slept, 0.1, "[ruby-core:18015]: longer than expected")
  end
end
